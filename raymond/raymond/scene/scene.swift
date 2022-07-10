import Foundation

struct Scene: Codable {
    struct Material: Codable {
        var nodes: [String: Node]
        
        init(from decoder: Decoder) throws {
            self.nodes = try [String: Node].init(from: decoder)
        }
        
        func encode(to encoder: Encoder) throws {
            try nodes.encode(to: encoder)
        }
    }
    
    struct Shape: Codable {
        var type: String
        var filepath: URL
        var materials: [String]
    }
    
    struct Entity: Codable {
        var shape: String
        var matrix: float4x4
        
        private enum CodingKeys: String, CodingKey {
            case shape
            case matrix
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            shape = try container.decode(String.self, forKey: .shape)
            
            let matrixEntries = try container.decode([Float].self, forKey: .matrix)
            matrix = float4x4()
            for y in 0..<4 {
                for x in 0..<4 {
                    matrix[x, y] = matrixEntries[4 * y + x]
                }
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(shape, forKey: .shape)
            
            var matrixEntries: [Float] = .init(repeating: 0, count: 16)
            for y in 0..<4 {
                for x in 0..<4 {
                    matrixEntries[4 * y + x] = matrix[x, y]
                }
            }
            try container.encode(matrixEntries, forKey: .matrix)
        }
    }

    var materials: [String: Material]
    var shapes: [String: Shape]
    var entities: [String: Entity]
}

struct SceneLoader {
    func makeScene(fromURL url: URL) throws -> Scene {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        var scene = try decoder.decode(Scene.self, from: data)
        for (shapeName, shape) in scene.shapes {
            if shape.materials.isEmpty {
                print("assigning random material to shape without materials: \(shapeName)!")
                scene.shapes[shapeName]!.materials = [ scene.materials.keys.first! ]
            }
            
            // make all relative paths of shapes absolute
            let filepath = URL(string: shape.filepath.relativePath, relativeTo: url)!.absoluteURL
            scene.shapes[shapeName]!.filepath = filepath
        }
        return scene
    }
}
