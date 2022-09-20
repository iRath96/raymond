import Foundation
import Metal
import MetalPerformanceShaders

struct SceneDescription: Codable {
    struct Visibility: Codable {
        var camera: Bool
        var diffuse: Bool
        var glossy: Bool
        var transmission: Bool
        var volume: Bool
        var shadow: Bool
    }
    
    struct Material: Codable {
        var nodes: [String: Node]
        
        init(from decoder: Decoder) throws {
            self.nodes = try [String: Node].init(from: decoder)
        }
        
        func encode(to encoder: Encoder) throws {
            try nodes.encode(to: encoder)
        }
    }
    
    enum LightError: Error {
        case unsupportedLightType
    }
    
    struct Light: Codable {
        var material: String
        var visibility: Visibility
        var castShadows: Bool
        var useMIS: Bool
        
        var kernel: LightKernel
        
        private enum CodingKeys: CodingKey {
            case type
            case material
            case visibility, cast_shadows, use_mis
            case parameters
        }
        
        static let kernels: [String: LightKernel.Type] = [
            "WORLD": WorldLight.self,
            "AREA":  AreaLight.self,
            "POINT": PointLight.self,
            "SPOT":  SpotLight.self,
            "SUN":   SunLight.self,
        ]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            guard let type = Light.kernels[type] else {
                throw LightError.unsupportedLightType
            }
            
            material = try container.decode(String.self, forKey: .material)
            visibility = try container.decode(Visibility.self, forKey: .visibility)
            castShadows = try container.decode(Bool.self, forKey: .cast_shadows)
            useMIS = try container.decode(Bool.self, forKey: .use_mis)
            kernel = try container.decode(type, forKey: .parameters)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            guard let type = Light.kernels.first(where: { type(of: kernel) == $0.value })?.key else {
                throw NodeError.unsupportedNodeType
            }
            
            try container.encode(type, forKey: .type)
            try container.encode(material, forKey: .material)
            try container.encode(visibility, forKey: .visibility)
            try container.encode(castShadows, forKey: .cast_shadows)
            try container.encode(useMIS, forKey: .use_mis)
            try kernel.encode(to: container.superEncoder(forKey: .parameters))
        }
    }
    
    struct Shape: Codable {
        var type: String
        var filepath: URL
        var materials: [String]
    }
    
    struct Entity: Codable {
        var shape: String
        var visibility: Visibility
        var matrix: float4x4
        
        private enum CodingKeys: String, CodingKey {
            case shape
            case visibility
            case matrix
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            shape = try container.decode(String.self, forKey: .shape)
            visibility = try container.decode(Visibility.self, forKey: .visibility)
            
            let matrixEntries = try container.decode([Float].self, forKey: .matrix)
            matrix = float4x4()
            for y in 0..<4 {
                for x in 0..<4 {
                    matrix[x, y] = matrixEntries[4 * y + x]
                }
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(shape, forKey: .shape)
            try container.encode(visibility, forKey: .visibility)
            
            var matrixEntries: [Float] = .init(repeating: 0, count: 16)
            for y in 0..<4 {
                for x in 0..<4 {
                    matrixEntries[4 * y + x] = matrix[x, y]
                }
            }
            try container.encode(matrixEntries, forKey: .matrix)
        }
    }
    
    struct Camera: Codable {
        struct Film: Codable {
            var width: Float
            var height: Float
        }
        
        struct DepthOfField: Codable {
            var focus: Float
            var fstop: Float
        }
        
        var nearClip: Float
        var farClip: Float
        var film: Film
        var transform: float4x4
        var depthOfField: DepthOfField?
        
        private enum CodingKeys: String, CodingKey {
            case nearClip = "near_clip"
            case farClip = "far_clip"
            case film
            case transform
            case depthOfField = "dof"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            nearClip = try container.decode(Float.self, forKey: .nearClip)
            farClip = try container.decode(Float.self, forKey: .farClip)
            film = try container.decode(Film.self, forKey: .film)
            depthOfField = try container.decodeIfPresent(DepthOfField.self, forKey: .depthOfField)
            
            let matrixEntries = try container.decode([Float].self, forKey: .transform)
            transform = float4x4()
            for y in 0..<4 {
                for x in 0..<4 {
                    transform[x, y] = matrixEntries[4 * y + x]
                }
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(nearClip, forKey: .nearClip)
            try container.encode(farClip, forKey: .farClip)
            try container.encode(film, forKey: .film)
            try container.encodeIfPresent(depthOfField, forKey: .depthOfField)
            
            var matrixEntries: [Float] = .init(repeating: 0, count: 16)
            for y in 0..<4 {
                for x in 0..<4 {
                    matrixEntries[4 * y + x] = transform[x, y]
                }
            }
            try container.encode(matrixEntries, forKey: .transform)
        }
    }
    
    struct RenderSettings: Codable {
        struct Resolution: Codable {
            var width: Float
            var height: Float
        }
        
        var resolution: Resolution
    }

    var materials: [String: Material]
    var lights: [String: Light]
    var shapes: [String: Shape]
    var entities: [String: Entity]
    var camera: Camera?
    var render: RenderSettings
}

struct SceneDescriptionLoader {
    func makeSceneDescription(fromURL url: URL) throws -> SceneDescription {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        var scene = try decoder.decode(SceneDescription.self, from: data)
        for (shapeName, shape) in scene.shapes {
            if shape.materials.isEmpty {
                print("assigning random material to shape without materials: \(shapeName)!")
                scene.shapes[shapeName]!.materials = [ scene.materials.keys.first! ]
            }
            
            // make all relative paths of shapes absolute
            let filepath = URL(string: shape.filepath.relativePath, relativeTo: url)!.absoluteURL
            scene.shapes[shapeName]!.filepath = filepath
        }
        return scene
    }
}

struct Scene {
    var mesh: Mesh
    var accelerationStructure: MPSInstanceAccelerationStructure
    var intersectionHandler: MTLComputePipelineState
    var shadowRayHandler: MTLComputePipelineState
    
    var projectionMatrix: float4x4
    var shaderFunctionTable: MTLVisibleFunctionTable
    var resourcesRead: [MTLResource]
    
    var instanceBuffer: MTLBuffer
    var contextBuffer: MTLBuffer
}

struct SceneLoader {
    private func prepareEnvironmentMapSampling(
        forLibrary library: MTLLibrary,
        withContext contextBuffer: MTLBuffer,
        andEncoder contextEncoder: MTLArgumentEncoder,
        resources: inout [MTLResource],
        shaderIndex: Int
    ) throws {
        let exponent = 11
        let resolution = 1 << exponent
        let mipmapSize = (0...exponent).map { (1 << (2 * $0)) }.reduce(0, +)
        NSLog("Building environment map of size \(resolution)^2")
        
        let device = library.device
        let mipmapBuffer = device.makeBuffer(type: Float.self, count: mipmapSize)!
        let pdfBuffer = device.makeBuffer(type: Float.self, count: resolution * resolution)!
        
        let queue = device.makeCommandQueue()!
        let commandBuffer = queue.makeCommandBuffer()!
        
        let lastLevelOffset = mipmapSize - resolution * resolution
        var bufferOffset = lastLevelOffset
        
        // MARK: build finest level of envmap
        
        let buildFunction = library.makeFunction(name: "buildEnvironmentMap")!
        let buildPipeline = try device.makeComputePipelineState(function: buildFunction)
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(buildPipeline)
            computeEncoder.setBuffer(contextBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(mipmapBuffer, offset: bufferOffset * MemoryLayout<Float>.stride, index: 1)
            computeEncoder.setBuffer(pdfBuffer, offset: 0, index: 2)
            computeEncoder.useResources(resources, usage: .read)
            computeEncoder.dispatchThreads(
                MTLSize(width: resolution, height: resolution, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            computeEncoder.endEncoding()
        }
        
        // MARK: build mipmap
        
        let reduceFunction = library.makeFunction(name: "reduceEnvironmentMap")!
        let reducePipeline = try device.makeComputePipelineState(function: reduceFunction)
        for exponent in stride(from: exponent - 1, through: 0, by: -1) {
            let currentResolution = 1 << exponent
            bufferOffset -= currentResolution * currentResolution
            
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(reducePipeline)
                computeEncoder.setBuffer(mipmapBuffer, offset: bufferOffset * MemoryLayout<Float>.stride, index: 0)
                computeEncoder.dispatchThreads(
                    MTLSize(width: currentResolution, height: currentResolution, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
                computeEncoder.endEncoding()
            }
        }
        
        assert(bufferOffset == 0)
        
        // MARK: normalize PDFs
        
        let normalizeFunction = library.makeFunction(name: "normalizeEnvironmentMap")!
        let normalizePipeline = try device.makeComputePipelineState(function: normalizeFunction)
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(normalizePipeline)
            computeEncoder.setBuffer(mipmapBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(pdfBuffer, offset: 0, index: 1)
            computeEncoder.dispatchThreads(
                MTLSize(width: resolution * resolution, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: normalizePipeline.threadExecutionWidth, height: 1, depth: 1))
            computeEncoder.endEncoding()
        }
        
        // MARK: write out
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let envmapOffset = 4 /// @todo hardcoded!
        contextEncoder.set(at: envmapOffset + 0, resolution)
        contextEncoder.setBuffer(pdfBuffer, offset: 0, index: envmapOffset + 1)
        contextEncoder.setBuffer(mipmapBuffer, offset: 0, index: envmapOffset + 2)
        resources.append(pdfBuffer)
        resources.append(mipmapBuffer)
    }
    
    private func testEnvironmentMapSampling(
        forLibrary library: MTLLibrary,
        withContext contextBuffer: MTLBuffer,
        resources: [MTLResource]
    ) throws {
        let device = library.device
        let sampleGridResolution = 1024
        let histogramResolution = 256 /// @todo hardcoded
        let histogramBuffer = device.makeBuffer(type: Float.self, count: histogramResolution * histogramResolution)!
        
        let queue = device.makeCommandQueue()!
        let commandBuffer = queue.makeCommandBuffer()!
        
        let testFunction = library.makeFunction(name: "testEnvironmentMapSampling")!
        let testPipeline = try device.makeComputePipelineState(function: testFunction)
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(testPipeline)
            computeEncoder.setBuffer(contextBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(histogramBuffer, offset: 0, index: 1)
            computeEncoder.useResources(resources, usage: .read)
            computeEncoder.dispatchThreads(
                MTLSize(width: sampleGridResolution, height: sampleGridResolution, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            computeEncoder.endEncoding()
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        try histogramBuffer.saveEXR(
            at: URL(filePath: "/Users/alex/Desktop/histogram.exr"),
            width: histogramResolution,
            height: histogramResolution)
        
        exit(0)
    }
    
    private func makeWorldShader(
        scene: SceneDescription,
        codegen: inout Codegen
    ) throws -> Int {
        NSLog("generating world shader")
        let world = scene.lights.first { type(of: $0.value.kernel) == WorldLight.self }?.value
        let worldShaderIndex = try codegen.addMaterial(scene.materials[world!.material]!)
        return worldShaderIndex
    }
    
    private func makeAreaLights(
        device: MTLDevice,
        scene: SceneDescription,
        codegen: inout Codegen
    ) throws -> (Int, MTLBuffer) {
        let lights = scene.lights.values.lazy.filter { $0.kernel is AreaLight }
        let count = lights.count
        var (buffer, ptr) = device.makeBufferAndPointer(type: NEEAreaLight.self, count: count)
        
        for light in lights {
            let kernel = light.kernel as! AreaLight
            ptr.initialize(to: .init(
                shaderIndex: Int32(try codegen.addMaterial(scene.materials[light.material]!)),
                transform: kernel.transform,
                color: kernel.power * kernel.color,
                isCircular: kernel.isCirular
            ))
            ptr = ptr.advanced(by: 1)
        }
        
        return (count, buffer)
    }
    
    private func makePointLights(
        device: MTLDevice,
        scene: SceneDescription,
        codegen: inout Codegen
    ) throws -> (Int, MTLBuffer) {
        let lights = scene.lights.values.lazy.filter { $0.kernel is PointLight }
        let count = lights.count
        var (buffer, ptr) = device.makeBufferAndPointer(type: NEEPointLight.self, count: count)
        
        for light in lights {
            let kernel = light.kernel as! PointLight
            ptr.initialize(to: .init(
                shaderIndex: Int32(try codegen.addMaterial(scene.materials[light.material]!)),
                location: kernel.location,
                radius: kernel.radius,
                color: kernel.color * kernel.power
            ))
            ptr = ptr.advanced(by: 1)
        }
        
        return (count, buffer)
    }
    
    func loadScene(fromURL url: URL, onDevice device: MTLDevice) throws -> Scene {
        let sceneDescription = try SceneDescriptionLoader().makeSceneDescription(fromURL: url)
        
        var instanceLoader = InstanceLoader()
        let entityNames = [String](sceneDescription.entities.keys.sorted())
        for entityName in entityNames {
            NSLog("adding entity \(entityName)")
            try instanceLoader.addEntity(sceneDescription.entities[entityName]!)
        }
        
        let instancing = try instanceLoader.build(withDevice: device)
        
        var meshLoader = MeshLoader()
        for shapeName in instancing.shapeNames {
            NSLog("adding shape \(shapeName)")
            try meshLoader.addShape(sceneDescription.shapes[shapeName]!)
        }
        
        NSLog("building acceleration structures")
        let mesh = try meshLoader.build(withDevice: device)
        
        let codegenOptions: Codegen.Options = []
        var codegen = Codegen(basePath: url, device: device, options: codegenOptions)
        for materialName in mesh.materialNames {
            NSLog("generating shader for \(materialName)")
            try codegen.addMaterial(sceneDescription.materials[materialName]!)
        }
        
        NSLog("generating light shaders")
        let worldShaderIndex = try makeWorldShader(scene: sceneDescription, codegen: &codegen)
        let (areaLightCount, areaLightBuffer) = try makeAreaLights(device: device, scene: sceneDescription, codegen: &codegen)
        let (pointLightCount, pointLightBuffer) = try makePointLights(device: device, scene: sceneDescription, codegen: &codegen)
        
        NSLog("compiling shaders")
        let library = try codegen.build()
        
        let linkedFunctions = MTLLinkedFunctions()
        linkedFunctions.functions = []
        if codegenOptions.contains(.useFunctionTable) {
            for index in 0..<mesh.materialNames.count {
                NSLog("making function material_\(index)")
                let function = library.makeFunction(name: "material_\(index)")!
                linkedFunctions.functions!.append(function)
            }
        }
        
        NSLog("making function handleIntersections")
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = library.makeFunction(
            name: "handleIntersections")
        descriptor.label = "handleIntersections"
        descriptor.linkedFunctions = linkedFunctions
        let intersectionHandler = try library.device.makeComputePipelineState(
            descriptor: descriptor,
            options: [],
            reflection: nil)
        
        let shadowDescriptor = MTLComputePipelineDescriptor()
        shadowDescriptor.computeFunction = library.makeFunction(
            name: "handleShadowRays")
        shadowDescriptor.label = "handleShadowRays"
        shadowDescriptor.linkedFunctions = linkedFunctions
        let shadowRayHandler = try library.device.makeComputePipelineState(
            descriptor: shadowDescriptor,
            options: [],
            reflection: nil)
        
        /*NSLog("saving to binary")
        let binDescriptor = MTLBinaryArchiveDescriptor()
        let binArchive = try device.makeBinaryArchive(descriptor: binDescriptor)
        try binArchive.addComputePipelineFunctions(descriptor: descriptor)
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        try binArchive.serialize(to: desktopURL.appending(path: "binary.metallib"))*/
        
        let fnTableDescriptor = MTLVisibleFunctionTableDescriptor()
        fnTableDescriptor.functionCount = mesh.materialNames.count + 1
        
        let shaderFunctionTable = intersectionHandler.makeVisibleFunctionTable(
            descriptor: fnTableDescriptor)!
        
        if codegenOptions.contains(.useFunctionTable) {
            for index in 0..<mesh.materialNames.count {
                let function = linkedFunctions.functions![index]
                shaderFunctionTable.setFunction(
                    intersectionHandler.functionHandle(function: function)!,
                    index: index)
            }
        }
        
        let instanceBuffer = device.makeBuffer(type: PerInstanceData.self, count: Int(instancing.instanceCount))!
        instanceBuffer.label = "Per instance data"
        let instances = instanceBuffer.contents().assumingMemoryBound(to: PerInstanceData.self)
        for index in 0..<Int(instancing.instanceCount) {
            let instanceData = instances.advanced(by: index)
            let shapeInfo = mesh.shapeInfos[Int(instancing.indicesArray[index])]
            instanceData.pointee = PerInstanceData(
                vertexOffset: shapeInfo.vertexOffset,
                faceOffset: shapeInfo.faceOffset,
                boundsMin: shapeInfo.boundsMin,
                boundsSize: shapeInfo.boundsMax - shapeInfo.boundsMin,
                pointTransform: instancing.pointTransforms[index],
                normalTransform: instancing.normalTransforms[index],
                visibility: instancing.visibility[index]
            )
        }
        
        let argumentEncoder = descriptor.computeFunction!.makeArgumentEncoder(
            bufferIndex: ShadingBufferIndex.context.rawValue)
        let contextBuffer = device.makeBuffer(
            length: argumentEncoder.encodedLength,
            options: .storageModeShared)!
        argumentEncoder.setArgumentBuffer(contextBuffer, offset: 0)

        var resourcesRead: [MTLResource] = []
        let textureOffset = 10
        for (index, texture) in codegen.textures.enumerated() {
            argumentEncoder.setTexture(texture, index: textureOffset + index)
            resourcesRead.append(texture)
        }

        NSLog("building top level AS")
        let accelerationStructure = MPSInstanceAccelerationStructure(group: mesh.accelerationGroup)
        accelerationStructure.accelerationStructures = mesh.accelerationStructures
        accelerationStructure.instanceCount = Int(instancing.instanceCount)
        accelerationStructure.instanceBuffer = instancing.indices
        accelerationStructure.transformType = .float4x4
        accelerationStructure.transformBuffer = instancing.transforms
        accelerationStructure.rebuild()
        NSLog("done!")
        
        var projectionMatrix = float4x4(rows: [
            SIMD4([ 0, 0, 1, 314.8 ]),
            SIMD4([ 1, 0, 0, -248.2 ]),
            SIMD4([ 0, 1, 0, 160.5 ]),
            SIMD4([ 0, 0, 0, 1 ]),
        ])
        
        if let camera = sceneDescription.camera {
            projectionMatrix = camera.transform
        }
        
        // MARK: next event
        
        let neeOffset = 0 /// @todo hardcoded!
        argumentEncoder.set(at: neeOffset + 0, 1 + areaLightCount + pointLightCount)
        argumentEncoder.set(at: neeOffset + 1, areaLightCount)
        argumentEncoder.set(at: neeOffset + 2, pointLightCount)
        argumentEncoder.set(at: neeOffset + 3, worldShaderIndex)
        argumentEncoder.setBuffer(areaLightBuffer, offset: 0, index: neeOffset + 7)
        argumentEncoder.setBuffer(pointLightBuffer, offset: 0, index: neeOffset + 8)
        
        NSLog("preparing environmap sampling")
        try prepareEnvironmentMapSampling(
            forLibrary: library,
            withContext: contextBuffer,
            andEncoder: argumentEncoder,
            resources: &resourcesRead,
            shaderIndex: worldShaderIndex
        )
        NSLog("done!")
        
        /*try testEnvironmentMapSampling(
            forLibrary: library,
            withContext: contextBuffer,
            resources: resourcesRead)*/
        
        return Scene(
            mesh: mesh,
            accelerationStructure: accelerationStructure,
            intersectionHandler: intersectionHandler,
            shadowRayHandler: shadowRayHandler,
            projectionMatrix: projectionMatrix,
            shaderFunctionTable: shaderFunctionTable,
            resourcesRead: resourcesRead,
            instanceBuffer: instanceBuffer,
            contextBuffer: contextBuffer
        )
    }
}
