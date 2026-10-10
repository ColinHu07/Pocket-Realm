// Run on macOS with: swift scripts/validate_creatures.swift /absolute/path/to/Creatures /absolute/path/to/manifest.json
import Foundation
import RealityKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
struct Asset: Decodable {
    let meshes: Int
    let textures: Int
    let motionControls: [String]
}
let manifestURL = URL(fileURLWithPath: CommandLine.arguments[2])
let manifest = try JSONDecoder().decode([String: Asset].self, from: Data(contentsOf: manifestURL))
for name in manifest.keys.sorted() {
    let entity = try Entity.load(contentsOf: folder.appendingPathComponent(name + ".usdz"))
    let bounds = entity.visualBounds(relativeTo: nil)
    let size = bounds.extents
    precondition(size.y > 0.3 && size.y < 0.6, "Incorrect size: \(name)")
    var models = 0
    var paintedModels = 0
    var continuousBodies = 0
    func inspect(_ node: Entity) {
        if let model = node as? ModelEntity {
            models += 1
            if node.name.contains("continuous_body") { continuousBodies += 1 }
            for material in model.model!.materials {
                if let painted = material as? PhysicallyBasedMaterial,
                   painted.baseColor.texture != nil { paintedModels += 1 }
            }
            precondition(!model.model!.materials.isEmpty, "Missing materials: \(node.name)")
        }
        for child in node.children { inspect(child) }
    }
    inspect(entity)
    let expected = manifest[name]!
    for control in expected.motionControls {
        precondition(entity.findEntity(named: control) != nil, "Missing runtime motion control: \(control)")
    }
    precondition(models == expected.meshes, "Missing geometry: \(name)")
    precondition(continuousBodies == 1, "Missing sculpted body: \(name)")
    precondition(paintedModels == expected.textures, "Paint textures did not load: \(name)")
    print("\(name): \(models) model entities, \(size) meters, \(paintedModels) painted materials loaded")
}
print("All six assets and their motion controls load in RealityKit.")
