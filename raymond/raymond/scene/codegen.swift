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
            inputs[key] = "\(type)(\(makeIdentifier(link.node)).\(makeIdentifier(link.property)))"
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
                    case .enum(let ns, let v): kernelType += "k\(kernel)::\(ns)_\(v.uppercased())"
                    }
                    kernelType += idx < parameters.count-1 ? ",\n" : "\n"
                }
                kernelType += ">"
            }
            
            if inputs.isEmpty {
                text.addLine("\(kernelType) \(makeIdentifier(name!));")
            } else {
                text.addLine("\(kernelType) \(makeIdentifier(name!)) = {")
                text.indent()
                for input in inputs.sorted(by: { $0.0 < $1.0 }) {
                    text.addLine(".\(makeIdentifier(input.key)) = \(input.value),")
                }
                text.unindent()
                text.addLine("};")
            }
            text.addLine("\(makeIdentifier(name!)).compute(ctx, tctx);")
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
        var url: URL
        var options: [MTKTextureLoader.Option: Any]
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
            do {
                textureDescriptors[index].texture = try textureLoader.newTexture(
                    URL: textureDescriptors[index].url,
                    options: textureDescriptors[index].options
                )
            } catch {
                print("Could not load texture: \(error)")
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
        case let kernel as TexImageKernel:
            let slot = try registerTexture(kernel.filepath, kernel.colorspace)
            return .init(kernel: "TexImage", parameters: [
                .int(slot),
                .enum("INTERPOLATION", kernel.interpolation),
                .enum("PROJECTION", kernel.projection),
                .enum("EXTENSION", kernel.extension),
                .enum("ALPHA", kernel.alpha),
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
            return .init(kernel: "BsdfPrincipled", parameters: [
                .enum("DISTRIBUTION", kernel.distribution),
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
            
            return .init(kernel: "BsdfGlass", parameters: [
                .enum("DISTRIBUTION", "GGX")
            ])
        case is BsdfTranslucentKernel:
            warn("BsdfTranslucent: not implemented")
            return .init(kernel: "BsdfTranslucent")
        case is BumpKernel:
            warn("Bump: bump mapping not supported")
            return .init(kernel: "Bump")
        case is OutputMaterialKernel:
            return .init(kernel: "OutputMaterial")
        case is TexCoordKernel:
            return .init(kernel: "TextureCoordinate")
        case is ColorInvertKernel:
            return .init(kernel: "ColorInvert")
        case is BsdfTransparentKernel:
            return .init(kernel: "BsdfTransparent")
        case is AddShaderKernel:
            return .init(kernel: "AddShader")
        case is MixShaderKernel:
            return .init(kernel: "MixShader")
        case is SeparateColorKernel:
            return .init(kernel: "SeparateColor")
        case is HueSaturationKernel:
            return .init(kernel: "HueSaturation")
        case is LightPathKernel:
            warn("LightPath: support for this node is rudimentary")
            return .init(kernel: "LightPath")
        case is EmissionKernel:
            return .init(kernel: "Emission")
        case is NewGeometryKernel:
            return .init(kernel: "NewGeometry")
        case is BlackbodyKernel:
            warn("Blackbody: not implemented")
            return .init(kernel: "Blackbody")
        case is ColorCurvesKernel:
            warn("ColorCurves: not implemented")
            return .init(kernel: "ColorCurves")
        default:
            throw CodegenError.unsupportedKernel
        }
    }
    
    mutating func addMaterial(_ material: Scene.Material) throws {
        try emit(material)
    }
    
    private mutating func emit(_ material: Scene.Material) throws {
        state = [:]
        invocations = []
        
        for node in material.nodes.sorted(by: { $0.0 < $1.0 }) {
            if node.value.kernel is OutputMaterialKernel {
                // Only output nodes that are really needed
                try emitNode(material, key: node.key)
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
        
        let attributes = options.contains(.useFunctionTable) ? "[[visible]] " : ""
        text.addLine("""
        \(attributes)void material_\(materialIndex)(
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
        
        materialIndex += 1
    }
    
    private mutating func registerTexture(_ path: String, _ colorspace: String) throws -> Int {
        if let idx = textureIndices[path] {
            return idx
        }
        
        var options: [MTKTextureLoader.Option: Any] = [:]
        
        switch colorspace {
        case "Linear": options[.SRGB] = false
        case "sRGB": options[.SRGB] = true
        case "Non-Color":
            warn("colorspace: 'Non-Color' has not been tested")
            options[.SRGB] = false
        default:
            throw CodegenError.unsupportedColorSpace
        }
        
        let idx = textureDescriptors.count
        textureDescriptors.append(TextureDescriptor(
            url: URL(string: String(path.dropFirst(2)), relativeTo: basePath)!.absoluteURL,
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
        
        case .bgra8Unorm, .bgra8Unorm_srgb: return "RGBA"
        case .rgba16Unorm: return "RGBA"
        
        default: throw CodegenError.unsupportedTextureFormat
        }
    }
    
    private mutating func emitNode(_ material: Scene.Material, key: String) throws {
        switch state[key] {
            case .emitted: return
            case .pending: throw CodegenError.cycleDetected
            default: break
        }
        
        state[key] = .pending
        
        var node = material.nodes[key]!
        var invocation = try makeKernelInvocation(for: node.kernel)
        invocation.name = key
        
        if node.kernel is TexImageKernel {
            /// @todo hack!
            /// default values for some attributes don't make any sense
            /// (no idea why the blender API reports those in the first place)
            
            node.inputs["Vector"]!.value = nil
            invocation.assign(key: "Vector", value: "VECTOR(tctx.uv)")
        }
        
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
