import Foundation
import Metal
import MetalKit
import Rayjay

fileprivate let log = SwiftLogger(named: "codegen")

extension Dictionary {
    mutating func get(_ key: Key, otherwise fallback: @autoclosure () -> Value) -> Value {
        if let value = self[key] {
            return value
        }
        
        self[key] = fallback()
        return self[key]!
    }
}

extension String {
    var camelCase: String {
        get {
            if self.isEmpty {
                return ""
            }
            
            let trimmed = self.trimmingCharacters(in: [" "])
            return trimmed.first!.lowercased() + trimmed.capitalized.replacing(" ", with: "").dropFirst()
        }
    }
}

struct Codegen {
    struct Options {
        let externalCompile: Bool
        
        init(externalCompile: Bool = false) {
            self.externalCompile = externalCompile
        }
    }
    
    static func makeIdentifier(from name: String) -> String {
        return name.camelCase.replacing(/[^a-zA-Z0-9_]/, with: "_")
    }
    
    enum CodegenError: Error {
        case cycleDetected
        case multiInputDetected
        case unsupportedTextureFormat
        case unsupportedKernel(any NodeKernel.Type)
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
        mutating func assign(key: String, type: String, value: Node.Value) -> Self {
            switch value {
            case .scalar(let v):
                inputs[key] = "\(type)(\(v))"
            case .vector(let v):
                inputs[key] = "\(type)({ \(v.map { String($0) }.joined(separator: ", ")) })"
            }
            
            return self
        }
        
        @discardableResult
        mutating func assign(key: String, link: Node.Link, type: String) -> Self {
            let node = Codegen.makeIdentifier(from: link.node)
            let property = Codegen.makeIdentifier(from: link.property)
            inputs[key] = "\(type)(n_\(node).\(property))"
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
            
            let nodeName = "n_\(Codegen.makeIdentifier(from: name!))"
            if inputs.isEmpty {
                text.addLine("\(kernelType) \(nodeName);")
            } else {
                text.addLine("\(kernelType) \(nodeName) = {")
                text.indent()
                for input in inputs.sorted(by: { $0.0 < $1.0 }) {
                    text.addLine(".\(Codegen.makeIdentifier(from: input.key)) = \(input.value),")
                }
                text.unindent()
                text.addLine("};")
            }
            text.addLine("\(nodeName).compute(ctx, shading);")
        }
    }
    
    private enum NodeState {
        case pending
        case marked
        case emitted
    }
    
    private struct TextureDescriptor {
        var url: URL?
        var options: [MTKTextureLoader.Option: Any]?
        var texture: MTLTexture?
    }
    
    struct Function {
        var name: String
    }
    
    struct FunctionTable {
        var name: String
        var functions: [Int: Function] = [:]
        
        mutating func set(function: Function, at index: Int) {
            functions[index] = function
        }
    }
    
    private var device: MTLDevice
    private var options: Options
    private var textureLoader: MTKTextureLoader
    
    private var textureDescriptors: [TextureDescriptor] = []
    private(set) var textures: [MTLTexture] = []
    private var textureIndices: [URL: Int] = [:]
    
    private var usedFunctionNames: Set<String> = []
    private var functionTables: [FunctionTable] = []
    private var state: [String: NodeState] = [:]
    private var invocations: [KernelInvocation] = []
    private var text = CodegenOutput()
    
    init(device: MTLDevice, options: Options) {
        self.device = device
        self.options = options
        self.textureLoader = .init(device: device)
    }
    
    private mutating func loadTextures() throws {
        log.info("loading textures")
        DispatchQueue.concurrentPerform(iterations: textureDescriptors.count) { index in
            if let url = textureDescriptors[index].url {
                do {
                    textureDescriptors[index].texture = try textureLoader.newTexture(
                        URL: url,
                        options: textureDescriptors[index].options
                    )
                } catch {
                    log.error("Could not load texture \(url): \(error)")
                    
                    let descriptor = MTLTextureDescriptor()
                    descriptor.width = 1
                    descriptor.height = 1
                    descriptor.pixelFormat = .r8Unorm
                    textureDescriptors[index].texture = textureLoader.device.makeTexture(descriptor: descriptor)!
                }
            }
        }
        textures = textureDescriptors.map { $0.texture! }
        
        if textures.isEmpty {
            // Metal is sad when it has no textures :-(
            let descriptor = MTLTextureDescriptor()
            descriptor.width = 1
            descriptor.height = 1
            descriptor.pixelFormat = .r8Unorm
            textures.append(textureLoader.device.makeTexture(descriptor: descriptor)!)
        }
    }
    
    mutating func add(functionTable table: FunctionTable) {
        functionTables.append(table)
    }
    
    mutating func build() throws -> MTLLibrary {
        try loadTextures()
        
        log.info("building code")
        let metalEntryURL = Bundle.main.url(
            forResource: "entry",
            withExtension: "metal",
            subdirectory: "device"
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
        
        let dumpDirectory = Bundle.main.resourceURL!.absoluteURL
        // cannot use URL.temporaryDirectory here, because that uses symlinked paths that confuse the compiler (???)
        
        header += "\n"
        if options.externalCompile {
            /// not sure why, but our #includes need to be relative so that Xcode shader profiling works fully
            let relativePath = metalEntryURL.relativePath(from: dumpDirectory)!
            header += "#include \"\(relativePath)\"\n"
        } else {
            header += "#include \"\(metalEntryURL.relativePath)\"\n"
        }
        header += "\n"
        
        for functionTable in functionTables {
            header += "void \(functionTable.name)(MaterialIndex index, device Context &ctx, thread ShadingContext &shading) {\n"
            header += "    switch (index) {\n"
            for (index, function) in functionTable.functions.sorted(by: { $0.key < $1.key }) {
                header += "    case \(index):\n"
                header += "        void \(function.name)(device Context &, thread ShadingContext &);\n"
                header += "        \(function.name)(ctx, shading);\n"
                header += "        break;\n"
            }
            header += "    }\n"
            header += "}\n"
        }
        
        let source = "\(header)\n\(text.output)"
        print(source)
        
        if options.externalCompile {
            let libname = "raymond"
            let sourcePath = dumpDirectory.appending(path: "\(libname).metal")
            let airPath = dumpDirectory.appending(path: "\(libname).air")
            let libraryPath = dumpDirectory.appending(path: "\(libname).metallib")
            try source.write(to: sourcePath, atomically: true, encoding: .utf8)
            
            try shell("xcrun", "metal", "-c",
                "-gline-tables-only", "-frecord-sources",
                "-ffast-math",
                sourcePath.relativePath, "-o", airPath.relativePath)
            try shell("xcrun", "metallib",
                airPath.relativePath, "-o", libraryPath.relativePath)
            
            return try device.makeLibrary(URL: libraryPath)
        }
        
        let compileOptions = MTLCompileOptions()
        let library = try device.makeLibrary(source: source, options: compileOptions)
        return library
    }
    
    private mutating func makeKernelInvocation(for kernel: any NodeKernel) throws -> KernelInvocation {
        switch kernel {
        case let originalKernel as TexSkyKernel:
            var kernel = originalKernel
            var scale: Float = 1
            
            if kernel.type == "HOSEK_WILKIE" {
                log.warn("SkyKernel: ad-hoc mapping of Hosek-Wilkie to Nishita")
                
                let sunRotation = atan2(kernel.sunDirection[0], kernel.sunDirection[1])
                let sunElevation = asin(kernel.sunDirection[2])
                
                kernel.type = "NISHITA"
                kernel.sunDisc = false
                kernel.airDensity = 2
                kernel.dustDensity = 0.5
                kernel.ozoneDensity = 1
                kernel.sunElevation = max(sunElevation, 5 * Float.pi / 180)
                kernel.sunRotation = sunRotation
                
                scale = 0.08
            }
            
            if kernel.type == "NISHITA" {
                log.debug("generating sky texture")
                
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
                invocation.assign(key: "Data", value: .vector(data))
                invocation.assign(key: "Scale", value: .scalar(scale))
                return invocation
            }
            
            throw CodegenError.unsupportedKernel(type(of: kernel))
        case let kernel as TexImageKernel:
            let slot = try registerTexture(kernel.filepath)
            if kernel.alpha != "STRAIGHT" {
                log.warn("TexImage: alpha mode '\(kernel.alpha)' not supported")
            }
            switch kernel.colorspace {
            case "Linear": break
            case "sRGB": break
            default:
                log.warn("TexImage: colorspace '\(kernel.colorspace)' not supported")
            }
            switch kernel.extension {
            case "REPEAT": break
            default:
                log.warn("TexImage: extension '\(kernel.extension)' not supported")
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
                kernel.filepath.absoluteString
            ])
        case let kernel as TexEnvironmentKernel:
            let slot = try registerTexture(kernel.filepath)
            if kernel.alpha != "STRAIGHT" {
                log.warn("TexEnvironment: alpha mode '\(kernel.alpha)' not supported")
            }
            switch kernel.colorspace {
            case "Linear": break
            case "sRGB": break
            default:
                log.warn("TexEnvironment: colorspace '\(kernel.colorspace)' not supported")
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
                kernel.filepath.absoluteString
            ])
        case is TexCheckerKernel:
            return .init(kernel: "TexChecker")
        case let kernel as TexNoiseKernel:
            return .init(kernel: "TexNoise", parameters: [
                .enum("DIMENSION", kernel.dimension)
            ])
        case is TexIESKernel:
            log.warn("TexIES: not supported yet")
            return .init(kernel: "TexIES")
        case is TexMagicKernel:
            log.warn("TexMagic: not supported yet")
            return .init(kernel: "TexMagic")
        case is TexVoronoiKernel:
            log.warn("TexVoronoi: not supported yet")
            return .init(kernel: "TexVoronoi")
        case is TexMusgraveKernel:
            log.warn("TexMusgrave: not supported yet")
            return .init(kernel: "TexMusgrave")
        case let kernel as TexGradientKernel:
            return .init(kernel: "TexGradient", parameters: [
                .enum("TYPE", kernel.type)
            ])
        case let kernel as TexWaveKernel:
            return .init(kernel: "TexWave", parameters: [
                .enum("TYPE", kernel.type),
                .enum("DIRECTION", kernel.direction),
                .enum("PROFILE", kernel.profile)
            ])
        case is TexBrickKernel:
            log.warn("TexBrick: unsupported")
            return .init(kernel: "TexBrick")
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
        case let kernel as MixKernel:
            return .init(kernel: "Mix", parameters: [
                .bool(kernel.clampFactor),
                .bool(kernel.clampResult),
                .enum("FACTOR_MODE", kernel.factorMode)
            ])
        case let kernel as BsdfPrincipledKernel:
            if kernel.distribution != "GGX" {
                log.warn("BsdfPrincipled: only GGX distribution supported!")
            }
            return .init(kernel: "BsdfPrincipled", parameters: [
                .enum("DISTRIBUTION", "GGX"),
                .enum("SUBSURFACE_METHOD", kernel.subsurfaceMethod)
            ])
        case is AmbientOcclusionKernel:
            log.warn("AmbientOcclusion: unsupported")
            return .init(kernel: "AmbientOcclusion")
        case is VolumeScatterKernel:
            log.warn("VolumeScatter: unsupported")
            return .init(kernel: "VolumeScatter")
        case let kernel as MappingKernel:
            return .init(kernel: "Mapping", parameters: [
                .enum("TYPE", kernel.type)
            ])
        case let kernel as MapRangeKernel:
            return .init(kernel: "MapRange", parameters: [
                .bool(kernel.clamp),
                .enum("DATA_TYPE", kernel.dataType),
                .enum("INTERPOLATION_TYPE", kernel.interpolationType)
            ])
        case let kernel as NormalMappingKernel:
            if !kernel.uvMap.isEmpty {
                log.warn("NormalMapping: UV maps not yet supported")
            }
            return .init(kernel: "NormalMap", parameters: [
                .enum("SPACE", kernel.space)
            ])
        case is DisplacementKernel:
            log.warn("Displacement: not supported")
            return .init(kernel: "Displacement")
        case let kernel as BsdfGlassKernel:
            if kernel.distribution != "GGX" {
                log.warn("BsdfGlass: only GGX distribution supported!");
            }
            return .init(kernel: "BsdfGlass", parameters: [
                .enum("DISTRIBUTION", "GGX")
            ])
        case let kernel as BsdfGlossyKernel:
            if kernel.distribution != "GGX" {
                log.warn("BsdfGlossy: only GGX distribution supported!");
            }
            return .init(kernel: "BsdfGlossy", parameters: [
                .enum("DISTRIBUTION", "GGX")
            ])
        case is BsdfDiffuseKernel:
            log.warn("BsdfDiffuse: not tested")
            return .init(kernel: "BsdfDiffuse")
        case is BsdfVelvetKernel:
            log.warn("BsdfVelvet: unsupported")
            return .init(kernel: "BsdfVelvet")
        case is BsdfHairKernel:
            log.warn("BsdfHair: unsupported")
            return .init(kernel: "BsdfHair")
        case is BsdfTranslucentKernel:
            log.warn("BsdfTranslucent: not implemented")
            return .init(kernel: "BsdfTranslucent")
        case is BumpMappingKernel:
            log.warn("BumpMapping: not yet supported")
            return .init(kernel: "Bump")
        case is OutputMaterialKernel:
            return .init(kernel: "OutputMaterial")
        case is OutputWorldKernel:
            return .init(kernel: "OutputWorld")
        case is OutputLightKernel:
            return .init(kernel: "OutputLight")
        case is AttributeKernel:
            log.warn("Attribute: not yet supported")
            return .init(kernel: "Attribute")
        case let kernel as ValueKernel:
            var invocation: KernelInvocation = .init(kernel: "Value")
            return invocation.assign(key: "value", value: .scalar(kernel.value))
        case let kernel as RGBKernel:
            var invocation: KernelInvocation = .init(kernel: "RGB")
            return invocation.assign(key: "color", value: .vector([
                kernel.value.x,
                kernel.value.y,
                kernel.value.z,
                kernel.value.w
            ]))
        case is RGBToBWKernel:
            return .init(kernel: "RGBToBW")
        case is TexCoordKernel:
            return .init(kernel: "TextureCoordinate")
        case is NormalKernel:
            return .init(kernel: "NormalProduct")
        case let kernel as UVMapKernel:
            if !kernel.uvMap.isEmpty {
                log.warn("UVMap: UV maps not yet supported")
            }
            log.warn("UVMap: not tested")
            return .init(kernel: "UVMapCoordinate")
        case is ColorInvertKernel:
            return .init(kernel: "ColorInvert")
        case is BsdfTransparentKernel:
            return .init(kernel: "BsdfTransparent")
        case is BsdfRefractionKernel:
            log.warn("BsdfRefraction: not yet supported")
            return .init(kernel: "BsdfRefraction")
        case is BsdfAnisotropicKernel:
            log.warn("BsdfAnisotropic: not yet supported")
            return .init(kernel: "BsdfAnisotropic")
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
            log.warn("LightPath: support for this node is rudimentary")
            return .init(kernel: "LightPath")
        case is ObjectInfoKernel:
            log.warn("ObjectInfo: unsupported")
            return .init(kernel: "ObjectInfo")
        case is ParticleInfoKernel:
            log.warn("ParticleInfo: unsupported")
            return .init(kernel: "ParticleInfo")
        case is LightFalloffKernel:
            log.warn("LightFalloff: unsupported")
            return .init(kernel: "LightFalloff")
        case is VertexColorKernel:
            log.warn("VertexColor: unsupported")
            return .init(kernel: "VertexColor")
        case is EmissionKernel:
            return .init(kernel: "Emission")
        case is BackgroundKernel:
            return .init(kernel: "Background")
        case is NewGeometryKernel:
            return .init(kernel: "NewGeometry")
        case is BlackbodyKernel:
            return .init(kernel: "Blackbody")
        case is ColorCurvesKernel:
            log.warn("ColorCurves: not yet supported")
            return .init(kernel: "ColorCurves")
        case is FresnelKernel:
            return .init(kernel: "Fresnel")
        case is LayerWeightKernel:
            return .init(kernel: "LayerWeight")
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
            throw CodegenError.unsupportedKernel(type(of: kernel))
        }
    }
    
    private func findUnusedFunctionName(for name: String) -> String {
        let identifier = "s_" + Codegen.makeIdentifier(from: name)
        
        var index = 2
        var candidate = identifier
        while usedFunctionNames.contains(candidate) {
            candidate = "\(identifier)\(index)"
            index += 1
        }
        return candidate
    }
    
    mutating func add(material: Material, named name: String) throws -> Function {
        state = [:]
        invocations = []
        
        if material.hasSurfaceEmission() {
            log.debug("Material \(name) has surface emission")
        }
        
        for node in material.nodes.sorted(by: { $0.0 < $1.0 }) {
            // Only output nodes that are really needed
            if node.value.kernel is OutputMaterialKernel
            || node.value.kernel is OutputLightKernel
            || node.value.kernel is OutputWorldKernel {
                try emitNode(material, key: node.key)
            }
        }
        
        let functionName = findUnusedFunctionName(for: name)
        usedFunctionNames.insert(functionName)
        
        text.addLine("""
        void \(functionName)(
            device Context &ctx,
            thread ShadingContext &shading
        ) {
        """)
        text.indent()
        for invocation in invocations {
            invocation.output(&text)
        }
        text.unindent()
        text.addLine("}")
        text.addLine("")
        
        return .init(name: functionName)
    }
    
    private mutating func registerTexture(_ texture: MTLTexture) -> Int {
        let idx = textureDescriptors.count
        textureDescriptors.append(TextureDescriptor(texture: texture))
        return idx
    }
    
    private mutating func registerTexture(_ url: URL) throws -> Int {
        if let idx = textureIndices[url] {
            return idx
        }
        
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false
        ]
        
        let idx = textureDescriptors.count
        textureDescriptors.append(TextureDescriptor(
            url: url,
            options: options
        ))
        
        textureIndices[url] = idx
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
            log.warn("unsupported texture format: \(pixelFormat)")
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
        
        let mappedUV = "VECTOR(shading.uv)"
        let generatedUV = "VECTOR(shading.generated)"
        let normal = "VECTOR(shading.normal)"
        
        switch node.kernel {
        case is TexImageKernel:
            provideDefault(name: "Vector", value: mappedUV)
        case is TexCheckerKernel, is TexNoiseKernel, is TexEnvironmentKernel:
            provideDefault(name: "Vector", value: generatedUV)
        case is FresnelKernel,
             is LayerWeightKernel,
             is BsdfGlassKernel,
             is BsdfGlossyKernel,
             is BsdfDiffuseKernel,
             is BsdfPrincipledKernel,
             is BsdfTranslucentKernel,
             is BsdfRefractionKernel,
             is BsdfAnisotropicKernel,
             is BsdfVelvetKernel,
             is BumpMappingKernel:
            provideDefault(name: "Normal", value: normal)
        default: break
        }
    }
    
    private mutating func emitNode(_ material: Material, key: String) throws {
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
                    invocation.assign(key: key, type: value.type, value: v)
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

class MaterialBuilder {
    struct Result {
        let textures: [MTLTexture]
        let library: MTLLibrary
        
        func makeComputePipelineState(
            for function: String,
            constants: MTLFunctionConstantValues
        ) throws -> (MTLFunction, MTLComputePipelineState) {
            let descriptor = MTLComputePipelineDescriptor()
            descriptor.computeFunction = try library.makeFunction(name: function, constantValues: constants)
            descriptor.label = function
            
            return (descriptor.computeFunction!, try library.device.makeComputePipelineState(
                descriptor: descriptor,
                options: [],
                reflection: nil))
        }
    }
    
    enum MaterialType {
        case surface
        case light
    }
    
    private struct FunctionTableDescriptor {
        let type: MaterialType
        let name: String
    }
    
    private static let functionTables: [FunctionTableDescriptor] = [
        .init(type: .surface, name: "shadeSurface"),
        .init(type: .light, name: "shadeLight")
    ]
    
    private var shaderIndices: [MaterialType: [String: MaterialIndex]] = [
        .surface: [:],
        .light: [:]
    ]
    
    private var emissionCache: [String: Bool] = [:]
    
    private let library: [String: Material]
    public init(library: [String: Material]) {
        self.library = library
    }
    
    @discardableResult
    func index(of type: MaterialType, named name: String) -> MaterialIndex {
        let index = MaterialIndex(shaderIndices[type]!.count)
        return shaderIndices[type]!.get(name, otherwise: index)
    }
    
    func getShaderNames(_ type: MaterialType) -> [String] {
        return shaderIndices[type]!.sorted(by: { $0.value < $1.value }).map { $0.key }
    }
    
    func hasMaterialEmission(named name: String) -> Bool {
        return emissionCache.get(name, otherwise: library[name]!.hasSurfaceEmission())
    }
    
    func build(withDevice device: MTLDevice, options: Codegen.Options) throws -> Result {
        var codegen = Codegen(device: device, options: options)
        
        for fnTableDesc in Self.functionTables {
            var fnTable = Codegen.FunctionTable(name: fnTableDesc.name)
            for (name, index) in shaderIndices[fnTableDesc.type, default: [:]] {
                let function = try codegen.add(material: library[name]!, named: name)
                fnTable.set(function: function, at: Int(index))
            }
            codegen.add(functionTable: fnTable)
        }
        
        let library = try codegen.build()
        return .init(textures: codegen.textures, library: library)
    }
}
