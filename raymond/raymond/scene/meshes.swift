import Foundation
import Metal
import MetalPerformanceShaders

/**
 * @todo improve efficiency
 */
class FileReader {
    enum FileReaderError: Error {
        case unexpectedLine
        case unexpectedToken
    }
    
    var fileHandle: FileHandle
    private let bufferSize: Int = 1024
    private var buffer: Data
    
    private let asciiSpace = Character(" ").asciiValue!
    private let asciiNewline = Character("\n").asciiValue!
    
    init(withURL url: URL) throws {
        fileHandle = try FileHandle(forReadingFrom: url)
        buffer = Data(capacity: bufferSize)
    }
    
    private func readTokenOrLine(_ token: Bool) throws -> String {
        while true {
            var index: Int?
            for i in 0..<buffer.count {
                if (token && (buffer[i] == asciiSpace)) || buffer[i] == asciiNewline {
                    index = i
                    break
                }
            }
            
            if let index = index {
                let token = buffer.subdata(in: 0..<index)
                buffer.removeSubrange(0...index)
                return String(data: token, encoding: .ascii)!
            }
            
            let chunk = try fileHandle.read(upToCount: bufferSize)!
            if chunk.count == 0 {
                // end of file
                return String(data: buffer, encoding: .ascii)!
            }
            
            buffer.append(chunk)
        }
    }
    
    @discardableResult
    func readLine() throws -> String {
        return try readTokenOrLine(false)
    }
    
    @discardableResult
    func readToken() throws -> String {
        return try readTokenOrLine(true)
    }
    
    func assertLine(_ line: String) throws {
        guard try readLine() == line else {
            throw FileReaderError.unexpectedLine
        }
    }
    
    func assertToken(_ token: String) throws {
        guard try readToken() == token else {
            throw FileReaderError.unexpectedLine
        }
    }
}

struct Instancing {
    let instanceCount: UInt32
    let shapeNames: [String]
    
    let indices: MTLBuffer
    let transforms: MTLBuffer
    
    let indicesArray: [UInt32]
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
    
    mutating func addEntity(_ entity: Scene.Entity) throws {
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
            indicesArray: instances.map { $0.index }
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
        var materials: [UInt32]
        var vertexCount: UInt32
        var faceCount: UInt32
        
        var fileReader: FileReader
        
        private func assertToken(_ str: String) throws {
            guard try fileReader.readToken() == str else {
                throw MeshLoaderError.invalidShapeHeader
            }
        }
        
        init(withPath url: URL, materials: [UInt32]) throws {
            self.materials = materials
            fileReader = try FileReader(withURL: url)
            
            // read header
            
            try fileReader.assertLine("ply")
            try fileReader.assertLine("format ascii 1.0")
            try fileReader.assertToken("comment")
            try fileReader.readLine()
            
            try fileReader.assertToken("element")
            try fileReader.assertToken("vertex")
            vertexCount = UInt32(try fileReader.readToken())!
            
            try fileReader.assertLine("property float x")
            try fileReader.assertLine("property float y")
            try fileReader.assertLine("property float z")
            try fileReader.assertLine("property float nx")
            try fileReader.assertLine("property float ny")
            try fileReader.assertLine("property float nz")
            try fileReader.assertLine("property float s")
            try fileReader.assertLine("property float t")
            
            try fileReader.assertToken("element")
            try fileReader.assertToken("face")
            faceCount = UInt32(try fileReader.readToken())!
            
            try fileReader.assertLine("property list uchar uint vertex_indices")
            try fileReader.assertLine("property uchar material_index")
            try fileReader.assertLine("end_header")
        }
    }
    
    private var materialIds: [String: UInt32] = [:]
    private var shapeHandles: [ShapeHandle] = []
    
    mutating func addShape(_ shape: Scene.Shape) throws {
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
        
        let shapeHandle = try ShapeHandle(withPath: shape.filepath, materials: materials)
        shapeHandles.append(shapeHandle)
    }
    
    mutating func build(withDevice device: MTLDevice) throws -> Mesh {
        let totalVertexCount = Int(shapeHandles.reduce(0) { $0 + $1.vertexCount })
        let totalFaceCount = Int(shapeHandles.reduce(0) { $0 + $1.faceCount })
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
        
        var vertices = vertexBuffer.contents().assumingMemoryBound(to: Float.self)
        var indices = indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
        var normals = normalBuffer.contents().assumingMemoryBound(to: Float.self)
        var texCoords = texCoordBuffer.contents().assumingMemoryBound(to: Float.self)
        var materials = materialBuffer.contents().assumingMemoryBound(to: UInt32.self)
        
        for shapeHandle in shapeHandles {
            // read vertices
            for _ in 0..<shapeHandle.vertexCount {
                for dim in 0..<3 {
                    vertices.advanced(by: dim).pointee = Float(try shapeHandle.fileReader.readToken())!
                }
                
                for dim in 0..<3 {
                    normals.advanced(by: dim).pointee = Float(try shapeHandle.fileReader.readToken())!
                }
                
                for dim in 0..<2 {
                    texCoords.advanced(by: dim).pointee = Float(try shapeHandle.fileReader.readToken())!
                }
                
                vertices = vertices.advanced(by: 3)
                normals = normals.advanced(by: 3)
                texCoords = texCoords.advanced(by: 2)
            }
            
            // read faces
            for _ in 0..<shapeHandle.faceCount {
                let indexCount = Int(try shapeHandle.fileReader.readToken())!
                guard indexCount == 3 else {
                    throw MeshLoaderError.onlyTrianglesSupported
                }
                
                for dim in 0..<3 {
                    indices.advanced(by: dim).pointee = UInt32(try shapeHandle.fileReader.readToken())!
                }
                
                materials.pointee = shapeHandle.materials[Int(try shapeHandle.fileReader.readToken())!]
                
                indices = indices.advanced(by: 3)
                materials = materials.advanced(by: 1)
            }
        }
        
        // build acceleration structure
        let group = MPSAccelerationStructureGroup(device: device)
        
        var shapeInfo = Mesh.ShapeInfo(vertexOffset: 0, faceOffset: 0)
        var shapeInfos: [Mesh.ShapeInfo] = []
        
        let accelerationStructures = shapeHandles.map { shapeHandle in
            let triAccel = MPSTriangleAccelerationStructure(group: group)
            triAccel.vertexBuffer = vertexBuffer
            triAccel.vertexStride = 3 * MemoryLayout<Float>.stride
            triAccel.vertexBufferOffset = triAccel.vertexStride * Int(shapeInfo.vertexOffset)
            
            triAccel.indexBuffer = indexBuffer
            triAccel.indexType = .uInt32
            triAccel.indexBufferOffset = MemoryLayout<UInt32>.stride * Int(3 * shapeInfo.faceOffset)
            
            triAccel.triangleCount = Int(shapeHandle.faceCount)
            triAccel.rebuild()
            
            shapeInfos.append(shapeInfo)
            
            shapeInfo.vertexOffset += shapeHandle.vertexCount
            shapeInfo.faceOffset += shapeHandle.faceCount
            
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
