import Foundation
import Metal
import MetalPerformanceShaders
import Rayjay

fileprivate let log = Logger(named: "mesh")

class ShapeBuilder {
    struct Result {
        let indices: UnsafeMutablePointer<IndexTriplet>
        let vertices: UnsafeMutablePointer<Vertex>
        let materials: UnsafeMutablePointer<MaterialIndex>
        
        let accelerationGroup: MPSAccelerationStructureGroup
        let accelerationStructures: [MPSTriangleAccelerationStructure]
    }

    struct ShapeInfo {
        var vertexOffset: VertexIndex
        var faceOffset: FaceIndex
        var faceCount: FaceIndex
        var boundsMin: simd_float3
        var boundsMax: simd_float3
        var hasEmission: Bool
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
        var emissiveMaterials: [Bool]
        var hasEmission: Bool
        
        var vertexCount: VertexIndex
        var faceCount: FaceIndex
        
        var vertexOffset: VertexIndex
        var faceOffset: FaceIndex
        
        var boundsMin: simd_float3
        var boundsMax: simd_float3
        
        var fileReader: PLYReader
        
        init(
            withPath url: URL,
            materialIndices: [MaterialIndex], emissiveMaterials: [Bool], hasEmission: Bool,
            vertexOffset: VertexIndex, faceOffset: FaceIndex
        ) throws {
            self.path = url.relativePath
            self.fileReader = PLYReader(url: url)
            
            self.materialIndices = materialIndices
            self.emissiveMaterials = emissiveMaterials
            self.hasEmission = hasEmission
            
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
            vertexCount = VertexIndex(exactly: fileReader.readInt())!
            
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
            faceCount = FaceIndex(exactly: fileReader.readInt())!
            
            fileReader.assertLine("property list uchar uint vertex_indices")
            fileReader.assertLine("property uchar material_index")
            fileReader.assertLine("end_header")
            
            fileReader.close()
        }
    }
    
    private var shapeIds: [String: InstanceIndex] = [:]
    private var shapeHandles: [ShapeHandle] = []
    private var vertexOffset: VertexIndex = 0
    private var faceOffset: FaceIndex = 0
    
    @discardableResult
    func index(of name: String) throws -> InstanceIndex {
        if let id = shapeIds[name] {
            return id
        }
        
        let id = InstanceIndex(shapeIds.count)
        try add(shape: library[name]!)
        shapeIds[name] = id
        return id
    }
    
    private func add(shape: Shape) throws {
        guard shape.type == "ply" else {
            throw MeshLoaderError.unsupportedFormat
        }
        
        let materialIndices = shape.materials.map { material in
            materialBuilder.index(of: .surface, named: material)
        }
        
        let emissiveMaterials = shape.materials.map(materialBuilder.hasMaterialEmission)
        let hasEmission = emissiveMaterials.contains(where: { $0 })
        
        let shapeHandle = try ShapeHandle(
            withPath: shape.filepath,
            materialIndices: materialIndices,
            emissiveMaterials: emissiveMaterials,
            hasEmission: hasEmission,
            vertexOffset: vertexOffset,
            faceOffset: faceOffset
        )
        shapeHandles.append(shapeHandle)
        
        vertexOffset += shapeHandle.vertexCount
        faceOffset += shapeHandle.faceCount
    }
    
    func shapeInfo(for index: InstanceIndex) -> ShapeInfo {
        let shapeHandle = shapeHandles[Int(index)]
        return .init(
            vertexOffset: shapeHandle.vertexOffset,
            faceOffset: shapeHandle.faceOffset,
            faceCount: shapeHandle.faceCount,
            boundsMin: shapeHandle.boundsMin,
            boundsMax: shapeHandle.boundsMax,
            hasEmission: shapeHandle.hasEmission
        )
    }
    
    func build(
        withDevice device: MTLDevice,
        encoder: MTLArgumentEncoder,
        resources: inout [MTLResource]
    ) throws -> Result {
        let totalVertexCount = Int(vertexOffset)
        let totalFaceCount = Int(faceOffset)
        
        let (vertexBuffer, vertices)      = device.makeBufferAndPointer(type: Vertex.self, count: totalVertexCount)
        let (indexBuffer, indices)        = device.makeBufferAndPointer(type: IndexTriplet.self, count: totalFaceCount)
        let (normalBuffer, normals)       = device.makeBufferAndPointer(type: Normal.self, count: totalVertexCount)
        let (texCoordBuffer, texCoords)   = device.makeBufferAndPointer(type: TexCoord.self, count: totalVertexCount)
        let (materialBuffer, materials)   = device.makeBufferAndPointer(type: MaterialIndex.self, count: totalFaceCount)
        
        vertexBuffer.label = "Vertex buffer"
        indexBuffer.label = "Index buffer"
        normalBuffer.label = "Normal buffer"
        texCoordBuffer.label = "UV buffer"
        materialBuffer.label = "Material buffer"
        
        DispatchQueue.concurrentPerform(iterations: shapeHandles.count) { index in
        //for index in 0..<shapeHandles.count {
            var shapeHandle = shapeHandles[index]
            log.debug("parsing shape \(shapeHandle.path)")
            
            shapeHandle.fileReader.reopen()
            
            let shapeVertices = vertices.advanced(by: Int(shapeHandle.vertexOffset))
            shapeHandle.fileReader.readVertexElements(
                shapeHandle.vertexCount,
                vertices: shapeVertices,
                normals: normals.advanced(by: Int(shapeHandle.vertexOffset)),
                texCoords: texCoords.advanced(by: Int(shapeHandle.vertexOffset)),
                boundsMin: &shapeHandle.boundsMin,
                boundsMax: &shapeHandle.boundsMax)
            
            shapeHandle.materialIndices.withUnsafeBufferPointer { materialIndicesPtr in
                shapeHandle.fileReader.readFaces(
                    shapeHandle.faceCount,
                    vertices: shapeVertices,
                    indices: indices.advanced(by: Int(shapeHandle.faceOffset)),
                    materials: materials.advanced(by: Int(shapeHandle.faceOffset)),
                    fromPalette: materialIndicesPtr.baseAddress!)
            }
            
            shapeHandle.fileReader.close()
            
            shapeHandles[index] = shapeHandle
        }
        
        // MARK: build acceleration structure
        
        let group = MPSAccelerationStructureGroup(device: device)
        
        let accelerationStructures = shapeHandles.map { shapeHandle in
            log.debug("accelerating \(shapeHandle.path)")
            
            let triAccel = MPSTriangleAccelerationStructure(group: group)
            triAccel.vertexBuffer = vertexBuffer
            triAccel.vertexStride = MemoryLayout<Vertex>.stride
            triAccel.vertexBufferOffset = triAccel.vertexStride * Int(shapeHandle.vertexOffset)
            
            assert(VertexIndex.bitWidth == 32)
            triAccel.indexBuffer = indexBuffer
            triAccel.indexType = .uInt32
            triAccel.indexBufferOffset = MemoryLayout<IndexTriplet>.stride * Int(shapeHandle.faceOffset)
            
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
            indices: indices,
            vertices: vertices,
            materials: materials,
            
            accelerationGroup: group,
            accelerationStructures: accelerationStructures
        )
    }
}
