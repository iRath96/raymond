import Foundation

protocol NodeKernel: Codable {}

// MARK: - Shader kernels

struct BsdfTransparentKernel: NodeKernel {}

struct BsdfGlassKernel: NodeKernel {
    var distribution: String
}

struct BsdfPrincipledKernel: NodeKernel {
    var distribution: String
    var subsurfaceMethod: String
    
    private enum CodingKeys: String, CodingKey {
        case distribution
        case subsurfaceMethod = "subsurface_method"
    }
}

struct MixShaderKernel: NodeKernel {}
struct EmissionKernel: NodeKernel {}

// MARK: - Texture kernels

struct TexImageKernel: NodeKernel {
    var filepath: String
    var interpolation: String
    var projection: String
    var `extension`: String
    var source: String
    var colorspace: String
    var alpha: String
}

// MARK: - Color kernels

struct ColorRampKernel: NodeKernel {
    struct Element: Codable {
        var position: Float
        var color: [Float]
    }

    var colorMode: String
    var interpolation: String
    var hueInterpolation: String
    var elements: [Element]
    
    private enum CodingKeys: String, CodingKey {
        case colorMode = "color_mode"
        case interpolation
        case hueInterpolation = "hue_interpolation"
        case elements
    }
}

struct ColorMixKernel: NodeKernel {
    var blendType: String
    var useClamp: Bool
    
    private enum CodingKeys: String, CodingKey {
        case blendType = "blend_type"
        case useClamp = "use_clamp"
    }
}

struct ColorInvertKernel: NodeKernel {}
struct SeparateColorKernel: NodeKernel {}
struct HueSaturationKernel: NodeKernel {}

// MARK: - Math kernels

struct MappingKernel: NodeKernel {
    var type: String
}

struct NormalMapKernel: NodeKernel {
    var space: String
    var uvMap: String
    
    private enum CodingKeys: String, CodingKey {
        case space
        case uvMap = "uv_map"
    }
}

struct BumpKernel: NodeKernel {
    var invert: Bool
}

// MARK: - Input kernels
struct TexCoordKernel: NodeKernel {}
struct LightPathKernel: NodeKernel {}
struct NewGeometryKernel: NodeKernel {}

// MARK: - Output kernels
struct OutputMaterialKernel: NodeKernel {}

// MARK: - Nodes

enum NodeError: Error {
    case unsupportedNodeType
}

struct Node: Codable {
    struct Link: Codable {
        var node: String
        var property: String
        
        init(from decoder: Decoder) throws {
            var unkeyed = try decoder.unkeyedContainer()
            self.node = try unkeyed.decode(String.self)
            self.property = try unkeyed.decode(String.self)
        }
        
        func encode(to encoder: Encoder) throws {
            var unkeyed = encoder.unkeyedContainer()
            try unkeyed.encode(self.node)
            try unkeyed.encode(self.property)
        }
    }
    
    enum Value: Codable {
        case scalar(Float)
        case vector([Float])
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            do {
                self = .scalar(try container.decode(Float.self))
            } catch {
                self = .vector(try container.decode([Float].self))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .scalar(let a0):
                try container.encode(a0)
            case .vector(let a0):
                try container.encode(a0)
            }
        }
    }
    
    struct Input: Codable {
        var type: String
        var links: [Link]?
        var value: Value?
    }
    
    private enum CodingKeys: CodingKey {
        case type
        case inputs
        case parameters
    }
    
    var inputs: [String: Input]
    var kernel: NodeKernel
    
    static let kernels: [String: NodeKernel.Type] = [
        "TEX_IMAGE": TexImageKernel.self,
        "VALTORGB": ColorRampKernel.self,
        "MIX_RGB": ColorMixKernel.self,
        "BSDF_PRINCIPLED": BsdfPrincipledKernel.self,
        "MAPPING": MappingKernel.self,
        "NORMAL_MAP": NormalMapKernel.self,
        "BSDF_GLASS": BsdfGlassKernel.self,
        "BUMP": BumpKernel.self,
        "OUTPUT_MATERIAL": OutputMaterialKernel.self,
        "TEX_COORD": TexCoordKernel.self,
        "INVERT": ColorInvertKernel.self,
        "BSDF_TRANSPARENT": BsdfTransparentKernel.self,
        "MIX_SHADER": MixShaderKernel.self,
        "SEPARATE_COLOR": SeparateColorKernel.self,
        "HUE_SAT": HueSaturationKernel.self,
        "LIGHT_PATH": LightPathKernel.self,
        "EMISSION": EmissionKernel.self,
        "NEW_GEOMETRY": NewGeometryKernel.self
    ]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        guard let type = Node.kernels[type] else {
            throw NodeError.unsupportedNodeType
        }
        
        inputs = try container.decode([String: Input].self, forKey: .inputs)
        kernel = try container.decode(type, forKey: .parameters)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard let type = Node.kernels.first(where: { type(of: kernel) == $0.value})?.key else {
            throw NodeError.unsupportedNodeType
        }
        
        try container.encode(type, forKey: .type)
        try container.encode(inputs, forKey: .inputs)
        try kernel.encode(to: container.superEncoder(forKey: .parameters))
    }
}
