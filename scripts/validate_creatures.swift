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
    func inspect(_ node: Entity) {
        if let model = node as? ModelEntity {
            models += 1
            precondition(!model.model!.materials.isEmpty, "Missing materials: \(node.name)")
        }
        for child in node.children { inspect(child) }
    }
    inspect(entity)
    precondition(models > 20, "Missing geometry: \(name)")
    print("\(name): \(models) model entities, \(size) meters, materials loaded")
}
print("All three assets load in RealityKit.")
