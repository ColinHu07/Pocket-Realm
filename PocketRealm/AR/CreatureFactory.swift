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
        let bounds = root.visualBounds(relativeTo: root)
        root.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: bounds.extents)
            .offsetBy(translation: bounds.center)]))
        return root
    }

    static func color(_ friend: RealmFriend) -> UIColor {
        switch friend {
        case .mosskip: return UIColor(red: 0.51, green: 0.84, blue: 0.68, alpha: 1)
        case .glimlo: return UIColor(red: 1, green: 0.78, blue: 0.42, alpha: 1)
        case .pebblin: return UIColor(red: 0.76, green: 0.66, blue: 0.91, alpha: 1)
        case .bloopi: return UIColor(red: 0.40, green: 0.77, blue: 0.90, alpha: 1)
        case .nibbi: return UIColor(red: 0.95, green: 0.63, blue: 0.72, alpha: 1)
        case .cindlet: return UIColor(red: 1, green: 0.69, blue: 0.32, alpha: 1)
        }
    }

    static func keepsake(_ friend: RealmFriend) -> Entity {
        let root = Entity()
        let material = SimpleMaterial(color: color(friend), roughness: 0.28, isMetallic: false)
        let center = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [material])
        switch friend {
        case .mosskip: center.scale = [0.8, 1.3, 0.8]
        case .bloopi: center.scale = [1.1, 0.4, 0.9]
        case .cindlet: center.scale = [0.65, 1.4, 0.65]
        case .nibbi:
            // Five soft points around a golden center make the sugar-star keepsake.
            center.scale = .one * 0.7
            center.model?.materials = [SimpleMaterial(color: .systemYellow, roughness: 0.6, isMetallic: false)]
            for index in 0..<5 {
                let angle = Float(index) * 2 * .pi / 5
                let point = ModelEntity(mesh: .generateSphere(radius: 0.022), materials: center.model!.materials)
                point.position = [sin(angle)*0.045, cos(angle)*0.045, 0]
                root.addChild(point)
            }
        default: break
        }
        root.addChild(center)
        if friend == .mosskip {
            let leaf = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [SimpleMaterial(color: .systemMint, roughness: 0.6, isMetallic: false)])
            leaf.scale = [1.5, 0.3, 0.7]
            leaf.position = [0.022, 0.06, 0]
            root.addChild(leaf)
        }
        addSparkles(to: root, color: color(friend), sparkRadius: friend == .glimlo ? 0.01 : 0.005)
        return root
    }

    /// A ring of glowing sparks that marks a keepsake as collectible.
    static func addSparkles(to root: Entity, color: UIColor, radius: Float = 0.105, sparkRadius: Float = 0.005) {
        let glow = UnlitMaterial(color: color)
        for index in 0..<8 {
            let angle = Float(index) * .pi / 4
            let spark = ModelEntity(mesh: .generateSphere(radius: sparkRadius), materials: [glow])
            spark.position = [cos(angle) * radius, sin(angle) * radius, 0]
            root.addChild(spark)
        }
    }
}
