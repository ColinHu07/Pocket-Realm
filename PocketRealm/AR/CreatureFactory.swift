import RealityKit
import UIKit

/// Original Blender models, exported in meters with Y up and the face toward +Z.
enum CreatureFactory {
    static func make(_ friend: RealmFriend) throws -> Entity {
        guard let url = Bundle.main.url(forResource: friend.rawValue, withExtension: "usdz", subdirectory: "Creatures") else {
            throw PlanError.server("\(friend.name)'s model is missing from this build. Rebuild the app with its bundled Creatures folder.")
        }
        let root = Entity()
        root.name = "Friend"
        root.addChild(try Entity.load(contentsOf: url))
        return root
    }

    static func color(_ friend: RealmFriend) -> UIColor {
        switch friend {
        case .mosskip: return UIColor(red: 0.51, green: 0.84, blue: 0.68, alpha: 1)
        case .glimlo: return UIColor(red: 1, green: 0.78, blue: 0.42, alpha: 1)
        case .pebblin: return UIColor(red: 0.76, green: 0.66, blue: 0.91, alpha: 1)
        }
    }

    static func keepsake(_ friend: RealmFriend) -> Entity {
        let root = Entity()
        let material = SimpleMaterial(color: color(friend), roughness: 0.28, isMetallic: false)
        let center = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [material])
        center.scale = friend == .mosskip ? [0.8, 1.3, 0.8] : .one
        root.addChild(center)
        if friend == .mosskip {
            let leaf = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [SimpleMaterial(color: .systemMint, roughness: 0.6, isMetallic: false)])
            leaf.scale = [1.5, 0.3, 0.7]
            leaf.position = [0.022, 0.06, 0]
            root.addChild(leaf)
        }
        let glow = UnlitMaterial(color: color(friend))
        for index in 0..<8 {
            let angle = Float(index) * .pi / 4
            let spark = ModelEntity(mesh: .generateSphere(radius: friend == .glimlo ? 0.01 : 0.005), materials: [glow])
            spark.position = [cos(angle) * 0.105, sin(angle) * 0.105, 0]
            root.addChild(spark)
        }
        return root
    }
}
