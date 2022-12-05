import Foundation

@objc class SwiftLogger: NSObject {
    @objc static let shared = SwiftLogger(named: "global")
    
    let logger: OpaquePointer
    @objc public init(named name: String) {
        logger = logger_create(name)
    }
    
    @objc public func debug(_ text: String) { logger_log(logger, .debug, text) }
    @objc public func info(_ text: String) { logger_log(logger, .info, text) }
    @objc public func warn(_ text: String) { logger_log(logger, .warn, text) }
    @objc public func error(_ text: String) { logger_log(logger, .error, text) }
}
