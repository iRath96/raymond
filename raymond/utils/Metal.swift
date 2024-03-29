import Metal
import MetalKit
import Foundation

fileprivate let log = SwiftLogger(named: "extensions")

extension MTLArgumentEncoder {
    func get<T>(at offset: Int, _ type: T.Type) -> T {
        return constantData(at: offset).assumingMemoryBound(to: T.self).pointee
    }
    
    func set<T>(at offset: Int, _ value: T) {
        constantData(at: offset).assumingMemoryBound(to: T.self).pointee = value
    }
}

extension MTLDevice {
    func makeBuffer<T>(type: T.Type, count: Int = 1, options: MTLResourceOptions = [], name: String? = nil) -> MTLBuffer? {
        let buffer = makeBuffer(length: max(count, 1) * MemoryLayout<T>.stride, options: options)
        buffer?.label = name
        return buffer
    }
    
    func makeBufferAndPointer<T>(type: T.Type, count: Int, options: MTLResourceOptions = [], name: String? = nil) -> (MTLBuffer, UnsafeMutablePointer<T>) {
        let buffer = makeBuffer(length: max(count, 1) * MemoryLayout<T>.stride, options: options)!
        buffer.label = name
        let pointer = buffer.contents().assumingMemoryBound(to: type)
        return (buffer, pointer)
    }
}

extension MTLBuffer {
    func toArray<T>(type: T.Type) -> Array<T> {
        let elementCount = self.length / MemoryLayout<T>.stride
        let data = self.contents().bindMemory(to: type, capacity: elementCount)
        return (0..<elementCount).map { data[$0] }
    }

    func saveBinary(at url: URL) throws {
        let data = Data(bytesNoCopy: contents(), count: length, deallocator: .none)
        try data.write(to: url)
    }
    
    func saveEXR(at url: URL, width: Int, height: Int) throws {
        let err = UnsafeMutablePointer<Optional<UnsafePointer<CChar>>>.allocate(capacity: 1)
        err.pointee = UnsafePointer(bitPattern: 0)
        defer {
            err.deallocate()
        }
        
        SaveEXR(
            contents().bindMemory(to: Float.self, capacity: width * height),
            Int32(width), Int32(height),
            Int32(1),
            0,
            NSString(string: url.path).utf8String!,
            err
        )
        
        if let p = err.pointee {
            log.error(String(utf8String: p)!)
        } else {
            log.info("Saved to EXR file")
        }
    }
    
    func asArray<T>(ofType type: T.Type) -> [T] {
        let start = contents().assumingMemoryBound(to: T.self)
        let count = length / MemoryLayout<T>.stride
        return Array(UnsafeMutableBufferPointer(start: start, count: count))
    }
}

extension MTLTexture {
    func saveEXR(at url: URL, normalizedBy norm: Float = 1) {
        let numComponents = 4
        let bytesPerRow = 4 * width * MemoryLayout<Float>.stride // @todo hack
        let data = UnsafeMutableRawPointer.allocate(
            byteCount: bytesPerRow * height,
            alignment: 16
        )
        defer {
            data.deallocate()
        }
        
        // load image data
        getBytes(
            data,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )
        
        // normalize image data
        let buffer = data.bindMemory(to: Float.self, capacity: numComponents * width * height)
        for i in 0..<(width * height) {
            buffer[numComponents*i + 0] *= norm
            buffer[numComponents*i + 1] *= norm
            buffer[numComponents*i + 2] *= norm
            buffer[numComponents*i + 3] = 1
        }
        
        // write data out
        let err = UnsafeMutablePointer<Optional<UnsafePointer<CChar>>>.allocate(capacity: 1)
        err.pointee = UnsafePointer(bitPattern: 0)
        defer {
            err.deallocate()
        }
        
        SaveEXR(
            data.bindMemory(to: Float.self, capacity: numComponents * width * height),
            Int32(width), Int32(height),
            Int32(numComponents),
            0,
            NSString(string: url.path).utf8String!,
            err
        )
        
        if let p = err.pointee {
            log.error(String(utf8String: p)!)
        } else {
            log.info("Saved to EXR file")
        }
    }
}
