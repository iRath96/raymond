import Foundation

protocol LightKernel: Codable {}

struct WorldLight: LightKernel {}

struct PointLight: LightKernel {
    var power: Float
    var color: SIMD3<Float>
    var radius: Float
}

struct SpotLight: LightKernel {
    var power: Float
    var color: SIMD3<Float>
    var radius: Float
    
    var spotSize: Float
    var spotBlend: Float
    
    private enum CodingKeys: String, CodingKey {
        case power, color, radius
        case spotSize = "spot_size"
        case spotBlend = "spot_blend"
    }
}

struct SunLight: LightKernel {
    var power: Float
    var color: SIMD3<Float>
    var angle: Float
}
