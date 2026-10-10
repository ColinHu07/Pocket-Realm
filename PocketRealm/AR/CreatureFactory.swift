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
        // Export pivots are not guaranteed to coincide with the soles of the feet.
        let importedBounds = root.visualBounds(relativeTo: root)
        for child in root.children { child.position.y -= importedBounds.min.y }
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
        case .pufflo: return UIColor(red: 0.66, green: 0.77, blue: 0.92, alpha: 1)
        case .trufflet: return UIColor(red: 0.79, green: 0.47, blue: 0.38, alpha: 1)
        case .dottli: return UIColor(red: 0.96, green: 0.84, blue: 0.45, alpha: 1)
        }
    }

    static func questReward(_ friend: RealmFriend) -> Entity {
        let root = Entity()
        if friend == .nibbi {
            let cookie = ModelEntity(mesh: .generateSphere(radius: 0.09), materials: [SimpleMaterial(color: .init(red: 0.84, green: 0.58, blue: 0.29, alpha: 1), roughness: 0.8, isMetallic: false)])
            cookie.scale = [1, 1, 0.22]; root.addChild(cookie)
            for index in 0..<7 {
                let angle = Float(index) * 2 * .pi / 7
                let chip = ModelEntity(mesh: .generateSphere(radius: 0.009), materials: [SimpleMaterial(color: .brown, roughness: 1, isMetallic: false)])
                chip.position = [cos(angle) * 0.055, sin(angle) * 0.055, 0.018]; root.addChild(chip)
            }
        } else if friend == .cindlet {
            let toast = ModelEntity(mesh: .generateBox(size: [0.15, 0.17, 0.03]), materials: [SimpleMaterial(color: .init(red: 0.86, green: 0.57, blue: 0.25, alpha: 1), roughness: 1, isMetallic: false)])
            root.addChild(toast)
            for x: Float in [-0.018, 0.018] {
                let heart = ModelEntity(mesh: .generateSphere(radius: 0.025), materials: [SimpleMaterial(color: .systemPink, roughness: 0.7, isMetallic: false)])
                heart.scale = [0.8, 1.1, 0.25]; heart.position = [x, 0.015, 0.022]
                heart.orientation = simd_quatf(angle: x < 0 ? 0.5 : -0.5, axis: [0, 0, 1]); root.addChild(heart)
            }
        } else {
            for index in 0..<3 {
                let bubble = ModelEntity(mesh: .generateSphere(radius: 0.025 + Float(index) * 0.009), materials: [SimpleMaterial(color: color(friend), roughness: 0.1, isMetallic: true)])
                bubble.position = [Float(index - 1) * 0.075, Float(index % 2) * 0.07, 0]; root.addChild(bubble)
            }
        }
        return root
    }

    static func keepsake(_ friend: RealmFriend) -> Entity {
        let root = Entity()
        let material = SimpleMaterial(color: color(friend), roughness: 0.28, isMetallic: false)
        let center = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [material])
        switch friend {
        case .mosskip: center.scale = [0.8, 1.3, 0.8]
        case .bloopi: center.scale = [1.1, 0.4, 0.9]
        case .cindlet: center.scale = [0.65, 1.4, 0.65]
        case .pufflo: center.scale = [0.9, 1.1, 0.9]
        case .trufflet: center.scale = [0.45, 1.4, 0.16]
        case .dottli: center.scale = [1, 1, 0.25]
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
