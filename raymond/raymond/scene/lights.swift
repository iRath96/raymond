import Foundation

protocol LightKernel: Codable {}

struct WorldLight: LightKernel {}

extension simd_float3x4: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for col in [ self.columns.0, self.columns.1, self.columns.2 ] {
            for i in 0..<4 {
                try container.encode(col[i])
            }
        }
    }
    
    public init(from decoder: Decoder) throws {
        self.init()
        
        var container = try decoder.unkeyedContainer()
        func readSIMD4() throws -> SIMD4<Float> {
            var col = SIMD4<Float>()
            for i in 0..<4 {
                col[i] = try container.decode(Float.self)
            }
            return col
        }
        
        columns.0 = try readSIMD4()
        columns.1 = try readSIMD4()
        columns.2 = try readSIMD4()
    }
}

struct AreaLight: LightKernel {
    var transform: simd_float3x4
    var power: Float
    var color: SIMD3<Float>
    var spread: Float
    var isCirular: Bool
    
    private enum CodingKeys: String, CodingKey {
        case transform, power, color, spread
        case isCirular = "is_circular"
    }
}

struct PointLight: LightKernel {
    var location: SIMD3<Float>
    var power: Float
    var color: SIMD3<Float>
    var radius: Float
}

struct SpotLight: LightKernel {
    var location: SIMD3<Float>
    var direction: SIMD3<Float>
    var power: Float
    var color: SIMD3<Float>
    var radius: Float
    
    var spotSize: Float
    var spotBlend: Float
    
    private enum CodingKeys: String, CodingKey {
        case location, direction, power, color, radius
        case spotSize = "spot_size"
        case spotBlend = "spot_blend"
    }
}

struct SunLight: LightKernel {
    var direction: SIMD3<Float>
    var power: Float
    var color: SIMD3<Float>
    var angle: Float
}
