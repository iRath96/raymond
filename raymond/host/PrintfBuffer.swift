import Foundation
import Metal

fileprivate let log = SwiftLogger(named: "device")

struct PrintfBuffer {
    let buffer: MTLBuffer
    
    init(on device: MTLDevice, sized size: Int) {
        let headerSize = 8
        buffer = device.makeBuffer(length: headerSize + size)!
        
        let p = buffer.contents().assumingMemoryBound(to: UInt32.self)
        p.pointee = UInt32(size)
        p.advanced(by: 1).pointee = 0
    }
    
    func execute() {
        let contents = buffer.contents()
        execute_printf_buffer(
            contents.advanced(by: 8).assumingMemoryBound(to: CChar.self),
            contents.advanced(by: 4).assumingMemoryBound(to: UInt32.self).pointee
        )
        contents.advanced(by: 4).assumingMemoryBound(to: UInt32.self).pointee = 0
    }
    
    var constants: MTLFunctionConstantValues {
        get {
            let result = MTLFunctionConstantValues()
            var gpuAddr = buffer.gpuAddress
            result.setConstantValue(&gpuAddr, type: .ulong, index: PrintfBufferConstantIndex)
            return result
        }
    }
}
