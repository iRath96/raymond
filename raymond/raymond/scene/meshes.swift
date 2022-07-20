import Foundation
import Metal
import MetalPerformanceShaders

func normalTransformFromPointTransform(_ transform: float4x4) -> float3x3 {
    let inv = transform.inverse.transpose
    let result = float3x3(
        SIMD3(inv[0,0], inv[0,1], inv[0,2]),
        SIMD3(inv[1,0], inv[1,1], inv[1,2]),
        SIMD3(inv[2,0], inv[2,1], inv[2,2])
    )
    return result
}

struct Instancing {
    let instanceCount: UInt32
    let shapeNames: [String]
    
    let indices: MTLBuffer
    let transforms: MTLBuffer
    
    let indicesArray: [UInt32]
    let pointTransforms: [simd_float4x4]
    let normalTransforms: [simd_float3x3]
}

struct InstanceLoader {
    private var shapeIds: [String: UInt32] = [:]
    
    private struct Instance {
        let index: UInt32
        let transform: float4x4
    }
    
    private var instances: [Instance] = []
    
    private mutating func shapeId(forName name: String) -> UInt32 {
        if let id = shapeIds[name] {
            return id
        }
        
        let newId = UInt32(shapeIds.count)
        shapeIds[name] = newId
        return newId
    }
    
    mutating func addEntity(_ entity: SceneDescription.Entity) throws {
        let shapeId = shapeId(forName: entity.shape)
        instances.append(Instance(index: shapeId, transform: entity.matrix))
    }
    
    func build(withDevice device: MTLDevice) throws -> Instancing {
        let indexBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride * instances.count)!
        let transformBuffer = device.makeBuffer(length: MemoryLayout<float4x4>.stride * instances.count)!
        
        var indices = indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
        var transforms = transformBuffer.contents().assumingMemoryBound(to: float4x4.self)
        
        for instance in instances {
            indices.pointee = instance.index
            transforms.pointee = instance.transform
            
            indices = indices.advanced(by: 1)
            transforms = transforms.advanced(by: 1)
        }
        
        return Instancing(
            instanceCount: UInt32(instances.count),
            shapeNames: shapeIds.sorted(by: { $0.value < $1.value }).map { $0.key },
            indices: indexBuffer,
            transforms: transformBuffer,
            indicesArray: instances.map { $0.index },
            pointTransforms: instances.map { $0.transform },
            normalTransforms: instances.map {
                normalTransformFromPointTransform($0.transform)
            }
        )
    }
}

struct Mesh {
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let normals: MTLBuffer
    let texCoords: MTLBuffer
    let materials: MTLBuffer
    
    let accelerationGroup: MPSAccelerationStructureGroup
    let accelerationStructures: [MPSTriangleAccelerationStructure]
    
    struct ShapeInfo {
        var vertexOffset: UInt32
        var faceOffset: UInt32
        var boundsMin: simd_float3
        var boundsMax: simd_float3
    }
    
    var shapeInfos: [ShapeInfo]
    var materialNames: [String]
}

struct MeshLoader {
    enum MeshLoaderError: Error {
        case unsupportedFormat
        case invalidShapeHeader
        case onlyTrianglesSupported
    }
    
    private struct ShapeHandle {
        var path: String
        
        var materials: [UInt32]
        var vertexCount: UInt32
        var faceCount: UInt32
        var vertexOffset: UInt32
        var faceOffset: UInt32
        
        var boundsMin: simd_float3
        var boundsMax: simd_float3
        
        var fileReader: PLYReader
        
        init(withPath url: URL, materials: [UInt32], vertexOffset: UInt32, faceOffset: UInt32) throws {
            self.materials = materials
            self.path = url.relativeString
            self.fileReader = PLYReader(url: url)
            self.vertexOffset = vertexOffset
            self.faceOffset = faceOffset
            
            self.boundsMin = simd_float3(repeating: +Float.infinity)
            self.boundsMax = simd_float3(repeating: -Float.infinity)
            
            // read header
            
            fileReader.assertLine("ply")
            fileReader.assertLine("format ascii 1.0")
            fileReader.assertToken("comment")
            fileReader.readLine()
            
            fileReader.assertToken("element")
            fileReader.assertToken("vertex")
            vertexCount = UInt32(exactly: fileReader.readInt())!
            
            fileReader.assertLine("property float x")
            fileReader.assertLine("property float y")
            fileReader.assertLine("property float z")
            fileReader.assertLine("property float nx")
            fileReader.assertLine("property float ny")
            fileReader.assertLine("property float nz")
            fileReader.assertLine("property float s")
            fileReader.assertLine("property float t")
            
            fileReader.assertToken("element")
            fileReader.assertToken("face")
            faceCount = UInt32(exactly: fileReader.readInt())!
            
            fileReader.assertLine("property list uchar uint vertex_indices")
            fileReader.assertLine("property uchar material_index")
            fileReader.assertLine("end_header")
            
            fileReader.close()
        }
    }
    
    private var materialIds: [String: UInt32] = [:]
    private var shapeHandles: [ShapeHandle] = []
    private var vertexOffset: UInt32 = 0
    private var faceOffset: UInt32 = 0
    
    mutating func addShape(_ shape: SceneDescription.Shape) throws {
        guard shape.type == "ply" else {
            throw MeshLoaderError.unsupportedFormat
        }
        
        let materials = shape.materials.map {
            // map material names to indices
            if let id = materialIds[$0] {
                return id
            }
            
            let newId = UInt32(materialIds.count)
            materialIds[$0] = newId
            return newId
        }
        
        let shapeHandle = try ShapeHandle(
            withPath: shape.filepath,
            materials: materials,
            vertexOffset: vertexOffset,
            faceOffset: faceOffset
        )
        shapeHandles.append(shapeHandle)
        
        vertexOffset += shapeHandle.vertexCount
        faceOffset += shapeHandle.faceCount
    }
    
    mutating func build(withDevice device: MTLDevice) throws -> Mesh {
        let totalVertexCount = Int(vertexOffset)
        let totalFaceCount = Int(faceOffset)
        let totalIndexCount = 3 * totalFaceCount
        
        let vertexBuffer = device.makeBuffer(length: 3 * MemoryLayout<Float>.stride * totalVertexCount)!
        let indexBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride * totalIndexCount)!
        let normalBuffer = device.makeBuffer(length: 3 * MemoryLayout<Float>.stride * totalVertexCount)!
        let texCoordBuffer = device.makeBuffer(length: 2 * MemoryLayout<Float>.stride * totalVertexCount)!
        let materialBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride * totalFaceCount)!
        
        vertexBuffer.label = "Vertex buffer"
        indexBuffer.label = "Index buffer"
        normalBuffer.label = "Normal buffer"
        texCoordBuffer.label = "UV buffer"
        materialBuffer.label = "Material buffer"
        
        let vertices = vertexBuffer.contents().assumingMemoryBound(to: Float.self)
        let indices = indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
        let normals = normalBuffer.contents().assumingMemoryBound(to: Float.self)
        let texCoords = texCoordBuffer.contents().assumingMemoryBound(to: Float.self)
        let materials = materialBuffer.contents().assumingMemoryBound(to: UInt32.self)
        
        DispatchQueue.concurrentPerform(iterations: shapeHandles.count) { index in
        //for index in 0..<shapeHandles.count {
            var shapeHandle = shapeHandles[index]
            NSLog("parsing shape \(shapeHandle.path)")
            
            shapeHandle.fileReader.reopen()
            
            shapeHandle.fileReader.readVertexElements(
                shapeHandle.vertexCount,
                vertices: vertices.advanced(by: 3 * Int(shapeHandle.vertexOffset)),
                normals: normals.advanced(by: 3 * Int(shapeHandle.vertexOffset)),
                texCoords: texCoords.advanced(by: 2 * Int(shapeHandle.vertexOffset)),
                boundsMin: &shapeHandle.boundsMin,
                boundsMax: &shapeHandle.boundsMax)
            
            let palette = UnsafePointer<UInt32>(shapeHandle.materials)
            shapeHandle.fileReader.readFaces(
                shapeHandle.faceCount,
                indices: indices.advanced(by: 3 * Int(shapeHandle.faceOffset)),
                materials: materials.advanced(by: Int(shapeHandle.faceOffset)),
                fromPalette: palette)
            
            shapeHandle.fileReader.close()
            
            shapeHandles[index] = shapeHandle
        }
        
        // build acceleration structure
        let group = MPSAccelerationStructureGroup(device: device)
        
        var shapeInfos: [Mesh.ShapeInfo] = []
        let accelerationStructures = shapeHandles.map { shapeHandle in
            NSLog("accelerating \(shapeHandle.path)")
            
            let triAccel = MPSTriangleAccelerationStructure(group: group)
            triAccel.vertexBuffer = vertexBuffer
            triAccel.vertexStride = 3 * MemoryLayout<Float>.stride
            triAccel.vertexBufferOffset = triAccel.vertexStride * Int(shapeHandle.vertexOffset)
            
            triAccel.indexBuffer = indexBuffer
            triAccel.indexType = .uInt32
            triAccel.indexBufferOffset = MemoryLayout<UInt32>.stride * Int(3 * shapeHandle.faceOffset)
            
            triAccel.triangleCount = Int(shapeHandle.faceCount)
            triAccel.rebuild()
            
            shapeInfos.append(Mesh.ShapeInfo(
                vertexOffset: shapeHandle.vertexOffset,
                faceOffset: shapeHandle.faceOffset,
                boundsMin: shapeHandle.boundsMin,
                boundsMax: shapeHandle.boundsMax
            ))
            
            return triAccel
        }
        
        return Mesh(
            vertices: vertexBuffer,
            indices: indexBuffer,
            normals: normalBuffer,
            texCoords: texCoordBuffer,
            materials: materialBuffer,
            
            accelerationGroup: group,
            accelerationStructures: accelerationStructures,
            
            shapeInfos: shapeInfos,
            materialNames: materialIds.sorted(by: { $0.value < $1.value }).map { $0.key }
        )
    }
}
