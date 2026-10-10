// Run on macOS with: swift scripts/validate_creatures.swift /absolute/path/to/Creatures
import Foundation
import RealityKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ["Mosskip", "Glimlo", "Pebblin"] {
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
    let expectedModels = ["Mosskip": 15, "Glimlo": 16, "Pebblin": 10]
    let expectedPainted = ["Mosskip": 1, "Glimlo": 3, "Pebblin": 2]
    precondition(models == expectedModels[name], "Missing geometry: \(name)")
    precondition(continuousBodies == 1, "Missing sculpted body: \(name)")
    precondition(paintedModels == expectedPainted[name], "Paint textures did not load: \(name)")
    print("\(name): \(models) model entities, \(size) meters, \(paintedModels) painted materials loaded")
}
print("All three assets load in RealityKit.")
