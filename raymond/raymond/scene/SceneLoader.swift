import Foundation
import Metal
import MetalPerformanceShaders
import Rayjay

extension Dictionary {
    mutating func get(_ key: Key, default value: Value) -> Value {
        if let value = self[key] {
            return value
        }
        self[key] = value
        return self[key]!
    }
    
    mutating func getOrAdd(_ key: Key) -> Value where Value == Int {
        if let value = self[key] {
            return value
        }
        self[key] = count
        return self[key]!
    }
}

struct Scene {
    var accelerationStructure: MPSInstanceAccelerationStructure
    var intersectionHandler: MTLComputePipelineState
    var shadowRayHandler: MTLComputePipelineState
    
    var projectionMatrix: float4x4
    var resourcesRead: [MTLResource]
    var contextBuffer: MTLBuffer
}

struct SceneLoader {
    func loadScene(fromURL url: URL, onDevice device: MTLDevice) throws -> Scene {
        let sceneDescription = try Rayjay.SceneLoader().makeScene(fromURL: url)
        
        var materialRegistry = MaterialBuilder(
            library: sceneDescription.materials)
        let shapeRegistry = ShapeBuilder(
            library: sceneDescription.shapes,
            materialRegistry: materialRegistry)
        let lightRegistry = LightBuilder(
            library: sceneDescription.lights,
            materialRegistry: materialRegistry)
        let entityRegistry = try EntityBuilder(
            library: sceneDescription.entities,
            shapeRegistry: shapeRegistry)
        
        // STEP 1: build all the shaders, so the following stages can access pipeline state info
        let shading = try materialRegistry.build(withDevice: device)
        
        let (intersectionFunction, intersectionHandler) = try shading.makeComputePipelineState(for: "handleIntersections")
        let (_, shadowRayHandler) = try shading.makeComputePipelineState(for: "handleShadowRays")
        
        let argumentEncoder = intersectionFunction.makeArgumentEncoder(
            bufferIndex: ShadingBufferIndex.context.rawValue)
        let contextBuffer = device.makeBuffer(
            length: argumentEncoder.encodedLength,
            options: .storageModeShared)!
        argumentEncoder.setArgumentBuffer(contextBuffer, offset: 0)
        
        var resourcesRead: [MTLResource] = []
        let textureOffset = ContextBufferIndex.textures.rawValue
        for (index, texture) in shading.textures.enumerated() {
            argumentEncoder.setTexture(texture, index: textureOffset + index)
            resourcesRead.append(texture)
        }
        
        // STEP 2: build all the shapes
        let shapes = try shapeRegistry.build(
            withDevice: device,
            encoder: argumentEncoder,
            resources: &resourcesRead)
        
        // STEP 3: build all the entities
        let entities = try entityRegistry.build(
            withDevice: device,
            shapes: shapes,
            encoder: argumentEncoder,
            resources: &resourcesRead)
        
        // STEP 4: build all the lights
        try lightRegistry.build(
            withDevice: device,
            library: shading.library,
            context: contextBuffer,
            encoder: argumentEncoder,
            resources: &resourcesRead)
        
        var projectionMatrix = float4x4(rows: [
            SIMD4([ 0, 0, 1, 314.8 ]),
            SIMD4([ 1, 0, 0, -248.2 ]),
            SIMD4([ 0, 1, 0, 160.5 ]),
            SIMD4([ 0, 0, 0, 1 ]),
        ])
        
        if let camera = sceneDescription.camera {
            projectionMatrix = camera.transform
        }
        
        return Scene(
            accelerationStructure: entities.accelerationStructure,
            intersectionHandler: intersectionHandler,
            shadowRayHandler: shadowRayHandler,
            projectionMatrix: projectionMatrix,
            resourcesRead: resourcesRead,
            contextBuffer: contextBuffer
        )
    }
}
