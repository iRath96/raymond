import Foundation

protocol LightKernel: Codable {}

struct WorldLight: LightKernel {}

struct AreaLight: LightKernel {
    var transform: [Float]
    var irradiance: Float
    var color: SIMD3<Float>
    var spread: Float
    var isCirular: Bool
    
    private enum CodingKeys: String, CodingKey {
        case transform, irradiance, color, spread
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
