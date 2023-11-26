import Foundation
import Metal
import Rayjay

fileprivate let log = SwiftLogger(named: "mesh")

func newAccelerationStructureWithDescriptor(
    _ descriptor: MTLAccelerationStructureDescriptor,
    on device: MTLDevice
) -> MTLAccelerationStructure {
    // Query for the sizes needed to store and build the acceleration structure.
    let accelSize = device.accelerationStructureSizes(descriptor: descriptor)
    
    // Allocate an acceleration structure large enough for this descriptor. This method
    // doesn't actually build the acceleration structure, but rather allocates memory.
    let accelerationStructure = device.makeAccelerationStructure(size: accelSize.accelerationStructureSize)!
    
    // Allocate scratch space Metal uses to build the acceleration structure.
    // Use MTLResourceStorageModePrivate for the best performance because the sample
    // doesn't need access to buffer's contents.
    let scratchBuffer = device.makeBuffer(length: accelSize.buildScratchBufferSize, options: .storageModePrivate)!
    
    // Create a command buffer that performs the acceleration structure build.
    let queue = device.makeCommandQueue()!
    var commandBuffer = queue.makeCommandBuffer()!
    
    // Create an acceleration structure command encoder.
    var commandEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
    
    // Allocate a buffer for Metal to write the compacted accelerated structure's size into.
    let compactedSizeBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)!
    
    // Schedule the actual acceleration structure build.
    commandEncoder.build(
        accelerationStructure: accelerationStructure,
        descriptor: descriptor,
        scratchBuffer: scratchBuffer,
        scratchBufferOffset: 0)
    
    // Compute and write the compacted acceleration structure size into the buffer. You
    // must already have a built acceleration structure because Metal determines the compacted
    // size based on the final size of the acceleration structure. Compacting an acceleration
    // structure can potentially reclaim significant amounts of memory because Metal must
    // create the initial structure using a conservative approach.
    
    commandEncoder.writeCompactedSize(
        accelerationStructure: accelerationStructure,
        buffer: compactedSizeBuffer,
        offset: 0)
    
    // End encoding, and commit the command buffer so the GPU can start building the
    // acceleration structure.
    commandEncoder.endEncoding()
    
    commandBuffer.commit()
    
    // The sample waits for Metal to finish executing the command buffer so that it can
    // read back the compacted size.

    // Note: Don't wait for Metal to finish executing the command buffer if you aren't compacting
    // the acceleration structure, as doing so requires CPU/GPU synchronization. You don't have
    // to compact acceleration structures, but do so when creating large static acceleration
    // structures, such as static scene geometry. Avoid compacting acceleration structures that
    // you rebuild every frame, as the synchronization cost may be significant.
    
    commandBuffer.waitUntilCompleted()
    
    let compactedSize = compactedSizeBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee
    
    // Allocate a smaller acceleration structure based on the returned size.
    let compactedAccelerationStructure = device.makeAccelerationStructure(size: Int(compactedSize))!
    
    // Create another command buffer and encoder.
    commandBuffer = queue.makeCommandBuffer()!
    
    commandEncoder = commandBuffer.makeAccelerationStructureCommandEncoder()!
    
    // Encode the command to copy and compact the acceleration structure into the
    // smaller acceleration structure.
    commandEncoder.copyAndCompact(
        sourceAccelerationStructure: accelerationStructure,
        destinationAccelerationStructure: compactedAccelerationStructure)
    
    // End encoding and commit the command buffer. You don't need to wait for Metal to finish
    // executing this command buffer as long as you synchronize any ray-intersection work
    // to run after this command buffer completes. The sample relies on Metal's default
    // dependency tracking on resources to automatically synchronize access to the new
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    commandBuffer.waitUntilCompleted()
    
    return compactedAccelerationStructure
}


class ShapeBuilder {
    struct Result {
        let indices: UnsafeMutablePointer<IndexTriplet>
        let vertices: UnsafeMutablePointer<Vertex>
        let materials: UnsafeMutablePointer<MaterialIndex>
        
        let accelerationStructures: [MTLAccelerationStructure]
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
        
        let (vertexBuffer, vertices) = device.makeBufferAndPointer(
            type: Vertex.self, count: totalVertexCount, name: "Vertex Buffer")
        let (indexBuffer, indices) = device.makeBufferAndPointer(
            type: IndexTriplet.self, count: totalFaceCount, name: "Index Buffer")
        let (normalBuffer, normals) = device.makeBufferAndPointer(
            type: Normal.self, count: totalVertexCount, name: "Normal Buffer")
        let (texCoordBuffer, texCoords) = device.makeBufferAndPointer(
            type: TexCoord.self, count: totalVertexCount, name: "UV Buffer")
        let (materialBuffer, materials) = device.makeBufferAndPointer(
            type: MaterialIndex.self, count: totalFaceCount, name: "Material Buffer")
        
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

        try vertexBuffer.saveBinary(at: URL.desktopDirectory.appending(path: "vertex.bin"))
        try indexBuffer.saveBinary(at: URL.desktopDirectory.appending(path: "index.bin"))
        do {
            let url = URL.desktopDirectory.appending(path: "shapes.bin")
            var data = [UInt32]()
            for shapeHandle in shapeHandles {
                data.append(contentsOf: [ shapeHandle.faceCount, shapeHandle.vertexOffset, shapeHandle.faceOffset ])
            }
            try data.withUnsafeMutableBytes {
                try Data(bytesNoCopy: $0.baseAddress!, count: $0.count, deallocator: .none).write(to: url)
            }
        }
        
        // MARK: build acceleration structure
        
        let accelerationStructures = shapeHandles.map { shapeHandle in
            log.debug("accelerating \(shapeHandle.path)")
            
            let mtlGeom = MTLAccelerationStructureTriangleGeometryDescriptor()
            mtlGeom.vertexBuffer = vertexBuffer
            mtlGeom.vertexStride = MemoryLayout<Vertex>.stride
            mtlGeom.vertexBufferOffset = mtlGeom.vertexStride * Int(shapeHandle.vertexOffset)
            mtlGeom.indexBuffer = indexBuffer
            mtlGeom.indexType = .uint32
            mtlGeom.indexBufferOffset = MemoryLayout<IndexTriplet>.stride * Int(shapeHandle.faceOffset)
            mtlGeom.triangleCount = Int(shapeHandle.faceCount)
            mtlGeom.opaque = true
            
            let mtlAccel = MTLPrimitiveAccelerationStructureDescriptor()
            mtlAccel.geometryDescriptors = [ mtlGeom ]
            
            return newAccelerationStructureWithDescriptor(mtlAccel, on: device)
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
            
            accelerationStructures: accelerationStructures
        )
    }
}
