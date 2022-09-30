import Foundation
import Metal
import MetalPerformanceShaders
import Rayjay

class ShapeBuilder {
    struct Result {
        let accelerationGroup: MPSAccelerationStructureGroup
        let accelerationStructures: [MPSTriangleAccelerationStructure]
    }

    struct ShapeInfo {
        var vertexOffset: UInt32
        var faceOffset: UInt32
        var boundsMin: simd_float3
        var boundsMax: simd_float3
    }
    
    private let library: [String: Shape]
    private var materialBuilder: MaterialBuilder
    public init(library: [String: Shape], materialBuilder: MaterialBuilder) {
        self.library = library
        self.materialBuilder = materialBuilder
    }
    
    enum MeshLoaderError: Error {
        case unsupportedFormat
        case invalidShapeHeader
        case onlyTrianglesSupported
    }
    
    private struct ShapeHandle {
        var path: String
        
        var materialIndices: [MaterialIndex]
        var vertexCount: UInt32
        var faceCount: UInt32
        var vertexOffset: UInt32
        var faceOffset: UInt32
        
        var boundsMin: simd_float3
        var boundsMax: simd_float3
        
        var fileReader: PLYReader
        
        init(withPath url: URL, materialIndices: [MaterialIndex], vertexOffset: UInt32, faceOffset: UInt32) throws {
            self.materialIndices = materialIndices
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
    
    private var shapeIds: [String: Int] = [:]
    private var shapeHandles: [ShapeHandle] = []
    private var vertexOffset: UInt32 = 0
    private var faceOffset: UInt32 = 0
    
    @discardableResult
    func index(of name: String) throws -> Int {
        if let id = shapeIds[name] {
            return id
        }
        
        let id = shapeIds.count
        try add(shape: library[name]!)
        shapeIds[name] = id
        return id
    }
    
    private func add(shape: Shape) throws {
        guard shape.type == "ply" else {
            throw MeshLoaderError.unsupportedFormat
        }
        
        let materialIndices = shape.materials.map { material in
            MaterialIndex(materialBuilder.index(of: .surface, named: material))
        }
        
        let shapeHandle = try ShapeHandle(
            withPath: shape.filepath,
            materialIndices: materialIndices,
            vertexOffset: vertexOffset,
            faceOffset: faceOffset
        )
        shapeHandles.append(shapeHandle)
        
        vertexOffset += shapeHandle.vertexCount
        faceOffset += shapeHandle.faceCount
    }
    
    func shapeInfo(for index: Int) -> ShapeInfo {
        let shapeHandle = shapeHandles[index]
        return .init(
            vertexOffset: shapeHandle.vertexOffset,
            faceOffset: shapeHandle.faceOffset,
            boundsMin: shapeHandle.boundsMin,
            boundsMax: shapeHandle.boundsMax
        )
    }
    
    func build(withDevice device: MTLDevice, encoder: MTLArgumentEncoder, resources: inout [MTLResource]) throws -> Result {
        let totalVertexCount = Int(vertexOffset)
        let totalFaceCount = Int(faceOffset)
        let totalIndexCount = 3 * totalFaceCount
        
        let (vertexBuffer, vertices)    = device.makeBufferAndPointer(type: Float.self, count: 3 * totalVertexCount)
        let (indexBuffer, indices)      = device.makeBufferAndPointer(type: UInt32.self, count: totalIndexCount)
        let (normalBuffer, normals)     = device.makeBufferAndPointer(type: Float.self, count: 3 * totalVertexCount)
        let (texCoordBuffer, texCoords) = device.makeBufferAndPointer(type: Float.self, count: 2 * totalVertexCount)
        let (materialBuffer, materials) = device.makeBufferAndPointer(type: MaterialIndex.self, count: totalFaceCount)
        
        vertexBuffer.label = "Vertex buffer"
        indexBuffer.label = "Index buffer"
        normalBuffer.label = "Normal buffer"
        texCoordBuffer.label = "UV buffer"
        materialBuffer.label = "Material buffer"
        
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
            
            let palette = UnsafePointer<MaterialIndex>(shapeHandle.materialIndices)
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
            
            return triAccel
        }
        
        encoder.setBuffer(vertexBuffer, offset: 0, index: ContextBufferIndex.vertices.rawValue)
        encoder.setBuffer(indexBuffer, offset: 0, index: ContextBufferIndex.vertexIndices.rawValue)
        encoder.setBuffer(normalBuffer, offset: 0, index: ContextBufferIndex.normals.rawValue)
        encoder.setBuffer(texCoordBuffer, offset: 0, index: ContextBufferIndex.texcoords.rawValue)
        encoder.setBuffer(materialBuffer, offset: 0, index: ContextBufferIndex.materials.rawValue)
        
        resources.append(vertexBuffer)
        resources.append(indexBuffer)
        resources.append(normalBuffer)
        resources.append(texCoordBuffer)
        resources.append(materialBuffer)
        
        return .init(
            accelerationGroup: group,
            accelerationStructures: accelerationStructures
        )
    }
}
