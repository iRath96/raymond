import Foundation
import Metal
import MetalPerformanceShaders

struct SceneDescription: Codable {
    struct Material: Codable {
        var nodes: [String: Node]
        
        init(from decoder: Decoder) throws {
            self.nodes = try [String: Node].init(from: decoder)
        }
        
        func encode(to encoder: Encoder) throws {
            try nodes.encode(to: encoder)
        }
    }
    
    struct Shape: Codable {
        var type: String
        var filepath: URL
        var materials: [String]
    }
    
    struct Entity: Codable {
        var shape: String
        var matrix: float4x4
        
        private enum CodingKeys: String, CodingKey {
            case shape
            case matrix
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            shape = try container.decode(String.self, forKey: .shape)
            
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
            
            var matrixEntries: [Float] = .init(repeating: 0, count: 16)
            for y in 0..<4 {
                for x in 0..<4 {
                    matrixEntries[4 * y + x] = matrix[x, y]
                }
            }
            try container.encode(matrixEntries, forKey: .matrix)
        }
    }

    var materials: [String: Material]
    var shapes: [String: Shape]
    var entities: [String: Entity]
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
    
    var projectionMatrix: float4x4
    var shaderFunctionTable: MTLVisibleFunctionTable
    var resourcesRead: [MTLResource]
    
    var instanceBuffer: MTLBuffer
    var contextBuffer: MTLBuffer
}

struct SceneLoader {
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
        
        let codegenOptions: Codegen.Options = [ .useFunctionTable ]
        var codegen = Codegen(basePath: url, device: device, options: codegenOptions)
        for materialName in mesh.materialNames {
            NSLog("generating shader for \(materialName)")
            try codegen.addMaterial(sceneDescription.materials[materialName]!)
        }
        
        NSLog("generating shaders")
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
        
        /*NSLog("saving to binary")
        let binDescriptor = MTLBinaryArchiveDescriptor()
        let binArchive = try device.makeBinaryArchive(descriptor: binDescriptor)
        try binArchive.addComputePipelineFunctions(descriptor: descriptor)
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        try binArchive.serialize(to: desktopURL.appending(path: "binary.metallib"))*/
        
        let fnTableDescriptor = MTLVisibleFunctionTableDescriptor()
        fnTableDescriptor.functionCount = mesh.materialNames.count
        
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
        
        let instanceBuffer = device.makeBuffer(
            length: MemoryLayout<PerInstanceData>.stride * Int(instancing.instanceCount))!
        instanceBuffer.label = "Per instance data"
        let instances = instanceBuffer.contents().assumingMemoryBound(to: PerInstanceData.self)
        for index in 0..<Int(instancing.instanceCount) {
            let instanceData = instances.advanced(by: index)
            let shapeInfo = mesh.shapeInfos[Int(instancing.indicesArray[index])]
            instanceData.pointee = PerInstanceData(
                vertexOffset: shapeInfo.vertexOffset,
                faceOffset: shapeInfo.faceOffset,
                pointTransform: instancing.pointTransforms[index],
                normalTransform: instancing.normalTransforms[index]
            )
        }
        
        let argumentEncoder = descriptor.computeFunction!.makeArgumentEncoder(
            bufferIndex: ShadingBufferIndex.context.rawValue)
        let contextBuffer = device.makeBuffer(
            length: argumentEncoder.encodedLength,
            options: .storageModeShared)!
        argumentEncoder.setArgumentBuffer(contextBuffer, offset: 0)

        var resourcesRead: [MTLResource] = []
        for (index, texture) in codegen.textures.enumerated() {
            argumentEncoder.setTexture(texture, index: index)
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
        
        let projectionMatrix = float4x4([
            SIMD4([ 0, 0, 1, 314.8 ]),
            SIMD4([ 1, 0, 0, -248.2 ]),
            SIMD4([ 0, 1, 0, 160.5 ]),
            SIMD4([ 0, 0, 0, 1 ]),
        ])
        
        return Scene(
            mesh: mesh,
            accelerationStructure: accelerationStructure,
            intersectionHandler: intersectionHandler,
            projectionMatrix: projectionMatrix,
            shaderFunctionTable: shaderFunctionTable,
            resourcesRead: resourcesRead,
            instanceBuffer: instanceBuffer,
            contextBuffer: contextBuffer
        )
    }
}
