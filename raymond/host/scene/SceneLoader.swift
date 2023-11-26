import Foundation
import Metal
import MetalPerformanceShaders
import Rayjay

struct Scene {
    var accelerationStructure: MTLAccelerationStructure
    var intersectionHandler: MTLComputePipelineState
    var shadowRayHandler: MTLComputePipelineState
    var library: MTLLibrary
    
    var resourcesRead: [MTLResource]
    var contextBuffer: MTLBuffer
    var argumentEncoder: MTLArgumentEncoder

    var boundsMin: float3
    var boundsMax: float3
    
    var camera: DeviceCamera {
        get {
            return argumentEncoder.get(at: ContextBufferIndex.camera.rawValue, DeviceCamera.self)
        }
        set(camera) {
            argumentEncoder.set(at: ContextBufferIndex.camera.rawValue, camera)
        }
    }
}

struct SceneLoader {
    var externalCompile: Bool = false
    
    private func makeDefaultCamera() -> DeviceCamera {
        let transform = float4x4(rows: [
            SIMD4([ 1, 0, 0, 0 ]),
            SIMD4([ 0, 1, 0, 0 ]),
            SIMD4([ 0, 0, 1, 0 ]),
            SIMD4([ 0, 0, 0, 1 ]),
        ])
        return DeviceCamera(
            transform: transform,
            nearClip: 0.1, farClip: 100,
            focalLength: 2.5,
            shift: simd_float2(0, 0))
    }
    
    func loadScene(
        fromURL url: URL,
        onDevice device: MTLDevice,
        constants: MTLFunctionConstantValues
    ) throws -> Scene {
        let sceneDescription = try Rayjay.SceneLoader().makeScene(fromURL: url)
        
        let materialBuilder = MaterialBuilder(
            library: sceneDescription.materials)
        let shapeBuilder = ShapeBuilder(
            library: sceneDescription.shapes,
            materialBuilder: materialBuilder)
        let lightBuilder = LightBuilder(
            library: sceneDescription.lights,
            materialBuilder: materialBuilder)
        let entityBuilder = try EntityBuilder(
            library: sceneDescription.entities,
            lightBuilder: lightBuilder,
            shapeBuilder: shapeBuilder)
        
        // STEP 1: build all the shaders, so the following stages can access pipeline state info
        let shading = try materialBuilder.build(
            withDevice: device,
            options: .init(externalCompile: externalCompile))
        
        let (intersectionFunction, intersectionHandler) = try shading.makeComputePipelineState(
            for: "handleIntersections",
            constants: constants)
        let (_, shadowRayHandler) = try shading.makeComputePipelineState(
            for: "handleShadowRays",
            constants: constants)
        
        let argumentEncoder = intersectionFunction.makeArgumentEncoder(
            bufferIndex: ShadingBufferIndex.context.rawValue)
        let contextBuffer = device.makeBuffer(
            length: argumentEncoder.encodedLength,
            options: .storageModeShared)!
        contextBuffer.label = "Context Buffer"
        argumentEncoder.setArgumentBuffer(contextBuffer, offset: 0)
        
        var resourcesRead: [MTLResource] = []
        let textureOffset = ContextBufferIndex.textures.rawValue
        for (index, texture) in shading.textures.enumerated() {
            argumentEncoder.setTexture(texture, index: textureOffset + index)
            resourcesRead.append(texture)
        }
        
        // STEP 2: build all the shapes
        let shapes = try shapeBuilder.build(
            withDevice: device,
            encoder: argumentEncoder,
            resources: &resourcesRead)
        
        // STEP 3: build all the entities
        let entities = try entityBuilder.build(
            withDevice: device,
            shapes: shapes,
            encoder: argumentEncoder,
            resources: &resourcesRead)
        
        // STEP 4: build all the lights
        try lightBuilder.build(
            withDevice: device,
            library: shading.library,
            shapes: shapes,
            context: contextBuffer,
            encoder: argumentEncoder,
            resources: &resourcesRead)
        
        var scene = Scene(
            accelerationStructure: entities.accelerationStructure,
            intersectionHandler: intersectionHandler,
            shadowRayHandler: shadowRayHandler,
            library: shading.library,
            
            resourcesRead: resourcesRead,
            contextBuffer: contextBuffer,
            argumentEncoder: argumentEncoder,
            boundsMin: entities.boundsMin,
            boundsMax: entities.boundsMax
        )
        
        var camera = makeDefaultCamera()
        if let cameraDesc = sceneDescription.camera {
            camera.transform = cameraDesc.transform
            camera.nearClip = cameraDesc.nearClip
            camera.farClip = cameraDesc.farClip
            camera.shift = cameraDesc.shift
            
            let focalLength = cameraDesc.focalLength ?? 50
            camera.focalLength = focalLength / (cameraDesc.film.width / 2)

            print(camera)
        }
        scene.camera = camera
        
        return scene
    }
}
