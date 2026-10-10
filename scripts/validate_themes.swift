// swift scripts/validate_themes.swift /absolute/path/to/Themes
import Foundation
import RealityKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let names = ["ReefFan", "ReefSponges", "ReefKelp", "CavernAmethyst", "CavernQuartz", "CavernCopper",
             "WoodlandShelves", "WoodlandOysters", "WoodlandFern"]
for name in names {
    let entity = try Entity.load(contentsOf: folder.appendingPathComponent(name + ".usdz"))
    let bounds = entity.visualBounds(relativeTo: entity)
    precondition(bounds.extents.y > 0.35 && bounds.extents.y < 0.85, "Incorrect meter scale: \(name)")
    precondition(bounds.max.y < 0.02 && bounds.min.z >= -0.01 && bounds.max.z < 0.3,
                 "Incorrect upper wall attachment / Y-up orientation: \(name)")
    var models = 0, textured = 0, normals = 0
    func inspect(_ node: Entity) {
        if let model = node as? ModelEntity, let component = model.model {
            models += 1
            precondition(component.materials.count <= 4, "Too many material batches: \(name)")
            for material in component.materials {
                guard let pbr = material as? PhysicallyBasedMaterial else {
                    preconditionFailure("Missing PBR material: \(name)")
                }
                if pbr.baseColor.texture != nil { textured += 1 }
                if pbr.normal.texture != nil { normals += 1 }
            }
        }
        for child in node.children { inspect(child) }
    }
    inspect(entity)
    precondition(models == 1 && textured >= 1 && normals == textured, "Missing geometry or surface textures: \(name)")
    print("\(name): one mesh, \(textured) textured materials with normal maps, \(bounds.extents) meters")
}
print("All nine theme assets load in RealityKit with correct scale, orientation, and PBR textures.")
