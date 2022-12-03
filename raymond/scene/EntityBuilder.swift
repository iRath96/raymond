import Foundation
import Metal
import MetalPerformanceShaders
import Rayjay

fileprivate extension simd_float4x4 {
    var inner3x3: simd_float3x3 {
        .init(
            SIMD3(self[0, 0], self[0, 1], self[0, 2]),
            SIMD3(self[1, 0], self[1, 1], self[1, 2]),
            SIMD3(self[2, 0], self[2, 1], self[2, 2])
        )
    }
}

class EntityBuilder {
    struct Result {
        let accelerationStructure: MPSInstanceAccelerationStructure
    }
    
    private struct Instance {
        let instanceIndex: InstanceIndex
        let shapeIndex: InstanceIndex
        let shapeInfo: ShapeBuilder.ShapeInfo
        let transform: simd_float4x4
        let visibility: RayFlags
    }

    private let library: [String: Entity]
    private let lightBuilder: LightBuilder
    private let shapeBuilder: ShapeBuilder
    private var instances: [Instance] = []
    
    public init(library: [String: Entity], lightBuilder: LightBuilder, shapeBuilder: ShapeBuilder) throws {
        self.library = library
        self.lightBuilder = lightBuilder
        self.shapeBuilder = shapeBuilder
        
        for entity in library.values {
            try shapeBuilder.index(of: entity.shape)
        }
    }
    
    private func makeVisibility(from visibility: Visibility) -> RayFlags {
        var result: UInt8 = 0
        if visibility.contains(.camera)       { result |= RayFlags.camera.rawValue }
        if visibility.contains(.diffuse)      { result |= RayFlags.diffuse.rawValue }
        if visibility.contains(.glossy)       { result |= RayFlags.glossy.rawValue }
        if visibility.contains(.transmission) { result |= RayFlags.transmission.rawValue }
        if visibility.contains(.volume)       { result |= RayFlags.volume.rawValue }
        if visibility.contains(.shadow)       { result |= RayFlags.shadow.rawValue }
        return RayFlags(rawValue: result)!
    }
    
    private func add(entity: Entity) throws {
        let shapeIndex = try shapeBuilder.index(of: entity.shape)
        let shapeInfo = shapeBuilder.shapeInfo(for: shapeIndex)
        
        let instanceIndex = InstanceIndex(instances.count)
        instances.append(.init(
            instanceIndex: InstanceIndex(instanceIndex),
            shapeIndex: shapeIndex,
            shapeInfo: shapeInfo,
            transform: entity.matrix,
            visibility: makeVisibility(from: entity.visibility)))
    }
    
    func build(
        withDevice device: MTLDevice,
        shapes: ShapeBuilder.Result,
        encoder: MTLArgumentEncoder,
        resources: inout [MTLResource]
    ) throws -> Result {
        try library.values.forEach(add)
        
        var (indexBuffer, indices) = device.makeBufferAndPointer(type: InstanceIndex.self, count: instances.count)
        var (transformBuffer, transforms) = device.makeBufferAndPointer(type: float4x4.self, count: instances.count)
        var (instanceBuffer, instanceData) = device.makeBufferAndPointer(type: DevicePerInstanceData.self, count: instances.count)
        
        for instance in instances {
            let normalTransform = instance.transform.inner3x3.inverse.transpose
            
            var lightIndex = LightIndex.max
            var lightFaceOffset: FaceIndex = 0
            var lightFaceCount: FaceIndex = 0
            if instance.shapeInfo.hasEmission {
                let light = lightBuilder.add(shapeLight: .init(
                    instanceIndex: instance.instanceIndex,
                    faceOffset: instance.shapeInfo.faceOffset,
                    faceCount: instance.shapeInfo.faceCount,
                    vertexOffset: instance.shapeInfo.vertexOffset,
                    normalTransform: instance.transform.inner3x3))
                
                lightIndex = light.lightIndex
                lightFaceOffset = light.lightFaceOffset
                lightFaceCount = light.faceCount
            }
            
            indices.pointee = instance.shapeIndex
            transforms.pointee = instance.transform
            instanceData.pointee = .init(
                vertexOffset: instance.shapeInfo.vertexOffset,
                faceOffset: instance.shapeInfo.faceOffset,
                lightFaceOffset: lightFaceOffset,
                lightFaceCount: lightFaceCount,
                lightIndex: lightIndex,
                
                boundsMin: instance.shapeInfo.boundsMin,
                boundsSize: instance.shapeInfo.boundsMax - instance.shapeInfo.boundsMin,
                pointTransform: instance.transform,
                normalTransform: normalTransform,
                visibility: instance.visibility)
            
            indices = indices.advanced(by: 1)
            transforms = transforms.advanced(by: 1)
            instanceData = instanceData.advanced(by: 1)
        }
        
        assert(InstanceIndex.bitWidth == 32)
        let accelerationStructure = MPSInstanceAccelerationStructure(group: shapes.accelerationGroup)
        accelerationStructure.accelerationStructures = shapes.accelerationStructures
        accelerationStructure.instanceCount = instances.count
        accelerationStructure.instanceBuffer = indexBuffer
        accelerationStructure.transformType = .float4x4
        accelerationStructure.transformBuffer = transformBuffer
        accelerationStructure.rebuild()
        
        encoder.setBuffer(instanceBuffer, offset: 0, index: ContextBufferIndex.perInstanceData.rawValue)
        resources.append(instanceBuffer)
        
        return .init(
            accelerationStructure: accelerationStructure
        )
    }
}
