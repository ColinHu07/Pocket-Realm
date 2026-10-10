// swift scripts/validate_jungle.swift /absolute/path/to/Jungle
import Foundation
import RealityKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for palette in ["Forest", "Tropical"] {
    for shape in ["Trail", "Bloom", "Fern"] {
        let name = palette + shape
        let entity = try Entity.load(contentsOf: folder.appendingPathComponent(name + ".usdz"))
        let bounds = entity.visualBounds(relativeTo: entity)
        precondition(bounds.extents.y > 0.4 && bounds.extents.y < 1.0, "Incorrect Y-up meter scale: \(name)")
        precondition(bounds.max.y < 0.02 && bounds.min.z >= -0.01 && bounds.max.z < 0.2, "Incorrect wall attachment/orientation: \(name)")
        var models = 0, textured = 0, roughness = 0
        func inspect(_ node: Entity) {
            if let model = node as? ModelEntity, let component = model.model {
                models += 1
                precondition(component.materials.count <= 4, "Too many material batches")
                for material in component.materials {
                    guard let pbr = material as? PhysicallyBasedMaterial else { continue }
                    if pbr.baseColor.texture != nil { textured += 1 }
                    if pbr.roughness.texture != nil { roughness += 1 }
                }
            }
            for child in node.children { inspect(child) }
        }
        inspect(entity)
        precondition(models == 1 && textured == 1 && roughness == 1, "Missing batched geometry or leaf textures: \(name)")
        print("\(name): one mesh, leaf color + roughness textures, \(bounds.extents) meters")
    }
}
print("All six botanicals load in RealityKit with correct wall orientation.")
