import Foundation
import Metal
import MetalPerformanceShaders
import Rayjay

fileprivate func normalTransformFromPointTransform(_ transform: float4x4) -> float3x3 {
    let inv = transform.inverse.transpose
    let result = float3x3(
        SIMD3(inv[0,0], inv[0,1], inv[0,2]),
        SIMD3(inv[1,0], inv[1,1], inv[1,2]),
        SIMD3(inv[2,0], inv[2,1], inv[2,2])
    )
    return result
}

class EntityBuilder {
    struct Result {
        let accelerationStructure: MPSInstanceAccelerationStructure
    }

    private let library: [String: Entity]
    private let shapeRegistry: ShapeBuilder
    public init(library: [String: Entity], shapeRegistry: ShapeBuilder) throws {
        self.library = library
        self.shapeRegistry = shapeRegistry
        
        for entity in library.values {
            try shapeRegistry.index(of: entity.shape)
        }
    }
    
    private struct Instance {
        let index: UInt32
        let transform: float4x4
        let visibility: RayFlags
    }
    
    private func makeInstance(from entity: Entity) throws -> Instance {
        var visibility: UInt8 = 0
        if entity.visibility.contains(.camera)       { visibility |= RayFlags.camera.rawValue }
        if entity.visibility.contains(.diffuse)      { visibility |= RayFlags.diffuse.rawValue }
        if entity.visibility.contains(.glossy)       { visibility |= RayFlags.glossy.rawValue }
        if entity.visibility.contains(.transmission) { visibility |= RayFlags.transmission.rawValue }
        if entity.visibility.contains(.volume)       { visibility |= RayFlags.volume.rawValue }
        if entity.visibility.contains(.shadow)       { visibility |= RayFlags.shadow.rawValue }
        
        return Instance(
            index: UInt32(try shapeRegistry.index(of: entity.shape)),
            transform: entity.matrix,
            visibility: RayFlags(rawValue: visibility)!
        )
    }
    
    func build(
        withDevice device: MTLDevice,
        shapes: ShapeBuilder.Result,
        encoder: MTLArgumentEncoder,
        resources: inout [MTLResource]
    ) throws -> Result {
        let instances = try library.values.map { entity in
            try makeInstance(from: entity)
        }
        
        var (indexBuffer, indices) = device.makeBufferAndPointer(type: UInt32.self, count: instances.count)
        var (transformBuffer, transforms) = device.makeBufferAndPointer(type: float4x4.self, count: instances.count)
        var (instanceBuffer, instanceData) = device.makeBufferAndPointer(type: PerInstanceData.self, count: instances.count)
        
        for instance in instances {
            let shapeInfo = shapeRegistry.shapeInfo(for: Int(instance.index))
            indices.pointee = instance.index
            transforms.pointee = instance.transform
            instanceData.pointee = PerInstanceData(
                vertexOffset: shapeInfo.vertexOffset,
                faceOffset: shapeInfo.faceOffset,
                boundsMin: shapeInfo.boundsMin,
                boundsSize: shapeInfo.boundsMax - shapeInfo.boundsMin,
                pointTransform: instance.transform,
                normalTransform: normalTransformFromPointTransform(instance.transform),
                visibility: instance.visibility
            )
            
            indices = indices.advanced(by: 1)
            transforms = transforms.advanced(by: 1)
            instanceData = instanceData.advanced(by: 1)
        }
        
        let accelerationStructure = MPSInstanceAccelerationStructure(group: shapes.accelerationGroup)
        accelerationStructure.accelerationStructures = shapes.accelerationStructures
        accelerationStructure.instanceCount = instances.count
        accelerationStructure.instanceBuffer = indexBuffer
        accelerationStructure.transformType = .float4x4
        accelerationStructure.transformBuffer = transformBuffer
        accelerationStructure.rebuild()
        
        encoder.setBuffer(instanceBuffer, offset: 0, index: ContextBufferIndex.perInstanceData.rawValue)
        resources.append(instanceBuffer)
        
        return .init(accelerationStructure: accelerationStructure)
    }
}
