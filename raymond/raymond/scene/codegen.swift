import Foundation
import Metal
import MetalKit

extension String {
    var camelCase: String {
        get {
            if self.isEmpty {
                return ""
            }
            
            return self.first!.lowercased() + self.capitalized.replacing(" ", with: "").dropFirst()
        }
    }
}

struct Codegen {
    enum CodegenError: Error {
        case cycleDetected
        case multiInputDetected
        case unsupportedTextureFormat
        case unsupportedKernel
        case unsupportedColorSpace
    }
    
    private struct CodegenOutput {
        private var indentLevel = 0
        private(set) var output = ""
        
        mutating func indent() {
            indentLevel += 1
        }
        
        mutating func unindent() {
            indentLevel -= 1
        }
        
        mutating func addRaw(_ string: String) {
            output += string
        }
        
        mutating func addLine(_ string: String) {
            let indent = String(repeating: "\t", count: indentLevel)
            output += indent + string.replacing("\n", with: "\n\(indent)") + "\n"
        }
    }
    
    private struct KernelInvocation {
        enum Parameter {
            case int(Int)
            case bool(Bool)
            case constant(String)
            case `enum`(String, String)
        }
        
        var name: String?
        var kernel: String
        var parameters: [Parameter] = []
        var comments: [String] = []
        var inputs: [String: String] = [:]
        
        private func makeIdentifier(_ id: String) -> String {
            return id.camelCase.replacing(/[^a-zA-Z0-9_]/, with: "_")
        }
        
        @discardableResult
        mutating func assign(key: String, value: String) -> Self {
            inputs[key] = value
            return self
        }
        
        @discardableResult
        mutating func assign(key: String, value: Node.Value) -> Self {
            switch value {
            case .scalar(let v):
                inputs[key] = "\(v)"
            case .vector(let v):
                inputs[key] = "{ \(v.map { String($0) }.joined(separator: ", ")) }"
            }
            
            return self
        }
        
        @discardableResult
        mutating func assign(key: String, link: Node.Link, type: String) -> Self {
            inputs[key] = "\(type)(n_\(makeIdentifier(link.node)).\(makeIdentifier(link.property)))"
            return self
        }
        
        func output(_ text: inout CodegenOutput) {
            text.addLine("")
            
            for comment in comments {
                text.addLine("// \(comment)")
            }
            
            var kernelType = "\(kernel)"
            if !parameters.isEmpty {
                kernelType += "<\n"
                for (idx, parameter) in parameters.enumerated() {
                    kernelType += "\t"
                    switch parameter {
                    case .int(let v): kernelType += "\(v)"
                    case .bool(let v): kernelType += "\(v)"
                    case .constant(let v): kernelType += "\(v)"
                    case .enum(let ns, let v):
                        let vEscaped = v.replacing(/\W/, with: "_").uppercased()
                        kernelType += "k\(kernel)::\(ns)_\(vEscaped)"
                    }
                    kernelType += idx < parameters.count-1 ? ",\n" : "\n"
                }
                kernelType += ">"
            }
            
            let nodeName = "n_\(makeIdentifier(name!))"
            if inputs.isEmpty {
                text.addLine("\(kernelType) \(nodeName);")
            } else {
                text.addLine("\(kernelType) \(nodeName) = {")
                text.indent()
                for input in inputs.sorted(by: { $0.0 < $1.0 }) {
                    text.addLine(".\(makeIdentifier(input.key)) = \(input.value),")
                }
                text.unindent()
                text.addLine("};")
            }
            text.addLine("\(nodeName).compute(ctx, tctx);")
        }
    }
    
    private enum NodeState {
        case pending
        case marked
        case emitted
    }
    
    struct Options: OptionSet {
        let rawValue: Int
        static let useFunctionTable = Options(rawValue: 1 << 0)
    }
    
    private struct TextureDescriptor {
        var url: URL?
        var options: [MTKTextureLoader.Option: Any]?
        var texture: MTLTexture?
    }
    
    private var basePath: URL
    private var device: MTLDevice
    private var textureLoader: MTKTextureLoader
    
    private var textureDescriptors: [TextureDescriptor] = []
    private(set) var textures: [MTLTexture] = []
    private var textureIndices: [String: Int] = [:]
    
    private var materialIndex = 0
    private var state: [String: NodeState] = [:]
    private var invocations: [KernelInvocation] = []
    private var text = CodegenOutput()
    private(set) var options: Options
    
    init(basePath: URL, device: MTLDevice, options: Options) {
        self.basePath = basePath
        self.device = device
        self.options = options
        self.textureLoader = .init(device: device)
    }
    
    private mutating func loadTextures() throws {
        NSLog("loading textures")
        DispatchQueue.concurrentPerform(iterations: textureDescriptors.count) { index in
            if let url = textureDescriptors[index].url {
                do {
                    textureDescriptors[index].texture = try textureLoader.newTexture(
                        URL: url,
                        options: textureDescriptors[index].options
                    )
                } catch {
                    print("Could not load texture \(url): \(error)")
                    
                    let descriptor = MTLTextureDescriptor()
                    descriptor.width = 1
                    descriptor.height = 1
                    descriptor.pixelFormat = .r8Unorm
                    textureDescriptors[index].texture = textureLoader.device.makeTexture(descriptor: descriptor)!
                }
            }
        }
        textures = textureDescriptors.map { $0.texture! }
    }
    
    mutating func build() throws -> MTLLibrary {
        try loadTextures()
        
        NSLog("building code")
        let metalEntryURL = Bundle.main.url(
            forResource: "shading",
            withExtension: "hpp"
        )!
        
        var header = """
        // \(Date.now)
        
        #define JIT_COMPILED
        #define NUMBER_OF_TEXTURES \(textures.count)
        
        """
        
        for index in 0..<textures.count {
            let pixelFormat = textures[index].pixelFormat
            header += "#define TEX\(index)_PIXEL_FORMAT kTexImage::PIXEL_FORMAT_\(try mapPixelFormat(pixelFormat))\n"
        }
        
        if options.contains(.useFunctionTable) {
            header += "#define USE_FUNCTION_TABLE\n"
        } else {
            header += "#define SWITCH_SHADERS switch (shaderIndex) { \\\n"
            for index in 0..<materialIndex {
                header += "  case \(index): \\\n"
                header += "    void material_\(index)(device Context &, thread ThreadContext &); \\\n"
                header += "    material_\(index)(ctx, tctx); \\\n"
                header += "    break; \\\n"
            }
            header += "}\n"
        }
        
        header += "#include \"\(metalEntryURL.relativePath)\"\n"
        
        let source = "\(header)\n\(text.output)"
        print(source)
        
        let compileOptions = MTLCompileOptions()
        let library = try device.makeLibrary(source: source, options: compileOptions)
        return library
    }
    
    private func warn(_ message: String) {
        print("Warning: \(message)")
    }
    
    private mutating func makeKernelInvocation(for kernel: NodeKernel) throws -> KernelInvocation {
        switch kernel {
        case let kernel as TexSkyKernel:
            if kernel.type == "NISHITA" {
                NSLog("generating sky texture")
                
                let textureDescriptor = MTLTextureDescriptor()
                textureDescriptor.width = 512
                textureDescriptor.height = 512
                textureDescriptor.pixelFormat = .rgba32Float
                
                let texture = textureLoader.device.makeTexture(descriptor: textureDescriptor)!
                let options = SkyOptions(
                    sunElevation: kernel.sunElevation,
                    sunRotation: kernel.sunRotation,
                    sunDisc: kernel.sunDisc,
                    sunSize: kernel.sunSize,
                    sunIntensity: kernel.sunIntensity,
                    altitude: kernel.altitude,
                    airDensity: kernel.airDensity,
                    dustDensity: kernel.dustDensity,
                    ozoneDensity: kernel.ozoneDensity
                )
                SkyLoader.generate(texture, with: options)
                
                var data = [Float].init(repeating: 0, count: 10)
                data.withUnsafeMutableBufferPointer { ptr in
                    SkyLoader.generateData(ptr.baseAddress!, with: options)
                }
                
                let slot = registerTexture(texture)
                var invocation: KernelInvocation = .init(kernel: "TexNishita", parameters: [
                    .int(slot)
                ])
                return invocation.assign(key: "data", value: "{ \(data.map { String($0) }.joined(separator: ", ")) }")
            }
            
            warn("SkyKernel: only Nishita supported")
            throw CodegenError.unsupportedKernel
        case let kernel as TexImageKernel:
            let slot = try registerTexture(kernel.filepath)
            if kernel.alpha != "STRAIGHT" {
                warn("TexImage: alpha mode '\(kernel.alpha)' not supported")
            }
            switch kernel.colorspace {
            case "Linear": break
            case "sRGB": break
            default:
                warn("TexImage: colorspace '\(kernel.colorspace)' not supported")
            }
            return .init(kernel: "TexImage", parameters: [
                .int(slot),
                .enum("INTERPOLATION", kernel.interpolation),
                .enum("PROJECTION", kernel.projection),
                .enum("EXTENSION", kernel.extension),
                .enum("ALPHA", "STRAIGHT"),
                .enum("COLOR_SPACE", kernel.colorspace),
                .constant("TEX\(slot)_PIXEL_FORMAT")
            ], comments: [
                kernel.filepath
            ])
        case let kernel as TexEnvironmentKernel:
            let slot = try registerTexture(kernel.filepath)
            if kernel.alpha != "STRAIGHT" {
                warn("TexEnvironment: alpha mode '\(kernel.alpha)' not supported")
            }
            switch kernel.colorspace {
            case "Linear": break
            case "sRGB": break
            default:
                warn("TexEnvironment: colorspace '\(kernel.colorspace)' not supported")
            }
            return .init(kernel: "TexImage", parameters: [
                .int(slot),
                .enum("INTERPOLATION", kernel.interpolation),
                .enum("PROJECTION", kernel.projection),
                .enum("EXTENSION", "REPEAT"),
                .enum("ALPHA", "STRAIGHT"),
                .enum("COLOR_SPACE", kernel.colorspace),
                .constant("TEX\(slot)_PIXEL_FORMAT")
            ], comments: [
                kernel.filepath
            ])
        case is TexCheckerKernel:
            return .init(kernel: "TexChecker")
        case let kernel as TexNoiseKernel:
            return .init(kernel: "TexNoise", parameters: [
                .enum("DIMENSION", kernel.dimension)
            ])
        case let kernel as ColorRampKernel:
            let elementStrings = kernel.elements.map { element in
                "\t{ \(element.position), { \(element.color.map { String($0) }.joined(separator: ", ")) } }"
            }.joined(separator: ",\n\t")
            
            var invocation = KernelInvocation(kernel: "ColorRamp", parameters: [
                .int(kernel.elements.count)
            ])
            return invocation.assign(key: "elements", value: "{\n\t\(elementStrings)\n\t}")
        case let kernel as ColorMixKernel:
            return .init(kernel: "ColorMix", parameters: [
                .enum("BLEND_TYPE", kernel.blendType),
                .bool(kernel.useClamp)
            ])
        case let kernel as BsdfPrincipledKernel:
            if kernel.distribution != "GGX" {
                warn("BsdfPrincipled: only GGX distribution supported!")
            }
            return .init(kernel: "BsdfPrincipled", parameters: [
                .enum("DISTRIBUTION", "GGX"),
                .enum("SUBSURFACE_METHOD", kernel.subsurfaceMethod)
            ])
        case let kernel as MappingKernel:
            return .init(kernel: "Mapping", parameters: [
                .enum("TYPE", kernel.type)
            ])
        case let kernel as NormalMapKernel:
            if !kernel.uvMap.isEmpty {
                warn("NormalMap: UV maps not yet supported")
            }
            return .init(kernel: "NormalMap", parameters: [
                .enum("SPACE", kernel.space)
            ])
        case is DisplacementKernel:
            warn("Displacement: not supported")
            return .init(kernel: "Displacement")
        case let kernel as BsdfGlassKernel:
            if kernel.distribution != "GGX" {
                warn("BsdfGlass: only GGX distribution supported!");
            }
            return .init(kernel: "BsdfGlass", parameters: [
                .enum("DISTRIBUTION", "GGX")
            ])
        case let kernel as BsdfGlossyKernel:
            if kernel.distribution != "GGX" {
                warn("BsdfGlossy: only GGX distribution supported!");
            }
            return .init(kernel: "BsdfGlossy", parameters: [
                .enum("DISTRIBUTION", "GGX")
            ])
        case is BsdfDiffuseKernel:
            warn("BsdfDiffuse: not tested")
            return .init(kernel: "BsdfDiffuse")
        case is BsdfTranslucentKernel:
            warn("BsdfTranslucent: not implemented")
            return .init(kernel: "BsdfTranslucent")
        case is BumpKernel:
            warn("Bump: bump mapping not supported")
            return .init(kernel: "Bump")
        case is OutputMaterialKernel:
            return .init(kernel: "OutputMaterial")
        case is OutputWorldKernel:
            return .init(kernel: "OutputWorld")
        case is TexCoordKernel:
            return .init(kernel: "TextureCoordinate")
        case let kernel as UVMapKernel:
            if !kernel.uvMap.isEmpty {
                warn("UVMap: UV maps not yet supported")
            }
            warn("UVMap: not tested")
            return .init(kernel: "UVMapCoordinate")
        case is ColorInvertKernel:
            return .init(kernel: "ColorInvert")
        case is BsdfTransparentKernel:
            return .init(kernel: "BsdfTransparent")
        case is AddShaderKernel:
            return .init(kernel: "AddShader")
        case is MixShaderKernel:
            return .init(kernel: "MixShader")
        case let kernel as SeparateColorKernel:
            return .init(kernel: "SeparateColor", parameters: [
                .enum("MODE", kernel.mode)
            ])
        case let kernel as CombineColorKernel:
            return .init(kernel: "CombineColor", parameters: [
                .enum("MODE", kernel.mode)
            ])
        case is HueSaturationKernel:
            return .init(kernel: "HueSaturation")
        case is BrightnessContrastKernel:
            return .init(kernel: "BrightnessContrast")
        case is GammaKernel:
            return .init(kernel: "Gamma")
        case is LightPathKernel:
            warn("LightPath: support for this node is rudimentary")
            return .init(kernel: "LightPath")
        case is EmissionKernel:
            return .init(kernel: "Emission")
        case is BackgroundKernel:
            return .init(kernel: "Background")
        case is NewGeometryKernel:
            return .init(kernel: "NewGeometry")
        case is BlackbodyKernel:
            return .init(kernel: "Blackbody")
        case is ColorCurvesKernel:
            warn("ColorCurves: not yet supported")
            return .init(kernel: "ColorCurves")
        case is FresnelKernel:
            return .init(kernel: "Fresnel")
        case is CombineVectorKernel:
            return .init(kernel: "CombineVector")
        case is SeparateVectorKernel:
            return .init(kernel: "SeparateVector")
        case let kernel as MathKernel:
            return .init(kernel: "Math", parameters: [
                .enum("OPERATION", kernel.operation),
                .bool(kernel.useClamp)
            ])
        case let kernel as VectorMathKernel:
            return .init(kernel: "VectorMath", parameters: [
                .enum("OPERATION", kernel.operation)
            ])
        default:
            throw CodegenError.unsupportedKernel
        }
    }
    
    mutating func addMaterial(_ material: SceneDescription.Material) throws {
        try emit(material, isWorld: false)
    }
    
    mutating func setWorld(_ world: SceneDescription.Material) throws {
        if options.contains(.useFunctionTable) {
            warn("""
            Function tables are not currently supported when world nodes are used.
            Somehow the combination of the two deadlocks the GPU, but it has not yet been determined why.
            Given that function tables are slower to compile and result in worse performance,
            we recommend not using them anyway.
            """)
            throw CodegenError.unsupportedKernel
        }
        try emit(world, isWorld: true)
    }
    
    private mutating func emit(_ material: SceneDescription.Material, isWorld: Bool) throws {
        state = [:]
        invocations = []
        
        for node in material.nodes.sorted(by: { $0.0 < $1.0 }) {
            // Only output nodes that are really needed
            if isWorld {
                if node.value.kernel is OutputWorldKernel {
                    try emitNode(material, key: node.key)
                }
            } else {
                if node.value.kernel is OutputMaterialKernel {
                    try emitNode(material, key: node.key)
                }
            }
        }
        
        if textures.isEmpty {
            // Metal doesn't like arrays of length zero, so we need to
            // create a fake texture for the argument buffer to work
            let descriptor = MTLTextureDescriptor()
            descriptor.width = 1
            descriptor.height = 1
            descriptor.pixelFormat = .r8Unorm
            textures.append(textureLoader.device.makeTexture(descriptor: descriptor)!)
        }
        
        let functionName = isWorld ? "world" : "material_\(materialIndex)"
        let attributes = options.contains(.useFunctionTable) ? "[[visible]] " : ""
        text.addLine("""
        \(attributes)void \(functionName)(
            device Context &ctx,
            thread ThreadContext &tctx
        ) {
        """)
        text.indent()
        for invocation in invocations {
            invocation.output(&text)
        }
        text.unindent()
        text.addLine("}")
        text.addLine("")
        
        if !isWorld {
            materialIndex += 1
        }
    }
    
    private mutating func registerTexture(_ texture: MTLTexture) -> Int {
        let idx = textureDescriptors.count
        textureDescriptors.append(TextureDescriptor(texture: texture))
        return idx
    }
    
    private mutating func registerTexture(_ path: String) throws -> Int {
        if let idx = textureIndices[path] {
            return idx
        }
        
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false
        ]
        
        let idx = textureDescriptors.count
        textureDescriptors.append(TextureDescriptor(
            url: URL(filePath: path),
            options: options
        ))
        
        textureIndices[path] = idx
        return idx
    }
    
    private func mapPixelFormat(_ pixelFormat: MTLPixelFormat) throws -> String {
        switch pixelFormat {
        case .r8Sint, .r8Uint, .r8Snorm, .r8Unorm, .r8Unorm_srgb: return "R"
        case .r16Sint, .r16Uint, .r16Snorm, .r16Unorm, .r16Float: return "R"
        case .r32Sint, .r32Uint, .r32Float: return "R"
        
        case .bgra8Unorm, .bgra8Unorm_srgb, .rgba8Unorm_srgb: return "RGBA"
        case .rgba16Unorm: return "RGBA"
        
        default:
            warn("unsupported texture format: \(pixelFormat)")
            return "RGBA"
            //throw CodegenError.unsupportedTextureFormat
        }
    }
    
    /**
     * Default values for some attributes do not make sense (e.g., normals being set to (0,0,0) on BSDFs).
     * There does not seem to be an elegant way to tell these attributes apart in the exporter plugin,
     * so we just fix the attributes here in the Codgen.
     *
     * @note This apparently also applies after inlining node groups in the exporter (for example, a 'normal' input on
     * a BSDF will still ignore a constant value that is provided to it through a NodeGroup!)
     */
    private func provideDefaults(forNode node: inout Node, inInvocation invocation: inout KernelInvocation) {
        func provideDefault(name: String, value: String) {
            node.inputs[name]!.value = nil
            invocation.assign(key: name, value: value)
        }
        
        let mappedUV = "VECTOR(tctx.uv)"
        let generatedUV = "VECTOR(tctx.generated)"
        let normal = "VECTOR(tctx.normal)"
        
        switch node.kernel {
        case is TexImageKernel:
            provideDefault(name: "Vector", value: mappedUV)
        case is TexCheckerKernel, is TexNoiseKernel, is TexEnvironmentKernel:
            provideDefault(name: "Vector", value: generatedUV)
        case is FresnelKernel,
             is BsdfGlassKernel,
             is BsdfGlossyKernel,
             is BsdfDiffuseKernel,
             is BsdfPrincipledKernel,
             is BsdfTranslucentKernel,
             is BumpKernel:
            provideDefault(name: "Normal", value: normal)
        default: break
        }
    }
    
    private mutating func emitNode(_ material: SceneDescription.Material, key: String) throws {
        switch state[key] {
            case .emitted: return
            case .pending: throw CodegenError.cycleDetected
            default: break
        }
        
        state[key] = .pending
        
        var node = material.nodes[key]!
        var invocation = try makeKernelInvocation(for: node.kernel)
        invocation.name = key
        
        provideDefaults(forNode: &node, inInvocation: &invocation)
        
        for (key, value) in node.inputs.sorted(by: { $0.0 < $1.0 }) {
            if value.links == nil || value.links!.isEmpty {
                if let v = value.value {
                    invocation.assign(key: key, value: v)
                }
            } else if value.links!.count == 1 {
                let link = value.links![0]
                try emitNode(material, key: link.node)
                
                invocation.assign(key: key, link: link, type: value.type)
            } else {
                throw CodegenError.multiInputDetected
            }
        }
        
        invocations.append(invocation)
        state[key] = .emitted
    }
}
