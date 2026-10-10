import RealityKit
import UIKit

/// A bundled, procedural forest spirit: no downloads or model conversion needed.
enum CreatureFactory {
    static func make() -> Entity {
        let root = Entity()
        let gold = UIColor(red: 1, green: 0.73, blue: 0.23, alpha: 1)
        let cream = UIColor(red: 1, green: 0.94, blue: 0.72, alpha: 1)
        let dark = UIColor(red: 0.12, green: 0.17, blue: 0.16, alpha: 1)
        func orb(_ radius: Float, _ color: UIColor, _ position: SIMD3<Float>, _ scale: SIMD3<Float> = [1, 1, 1]) {
            let material = SimpleMaterial(color: color, roughness: 0.65, isMetallic: false)
            let model = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
            model.position = position
            model.scale = scale
            root.addChild(model)
        }
        orb(0.12, gold, [0, 0.13, 0], [0.9, 1.05, 0.8])
        orb(0.105, gold, [0, 0.28, 0], [1.12, 0.95, 0.87])
        orb(0.07, cream, [0, 0.13, 0.071], [0.86, 1, 0.36])
        orb(0.045, gold, [-0.075, 0.38, 0], [0.52, 1.6, 0.55])
        orb(0.045, gold, [0.075, 0.38, 0], [0.52, 1.6, 0.55])
        orb(0.022, cream, [-0.075, 0.395, 0.018], [0.55, 1.65, 0.35])
        orb(0.022, cream, [0.075, 0.395, 0.018], [0.55, 1.65, 0.35])
        for x: Float in [-0.043, 0.043] {
            orb(0.018, dark, [x, 0.292, 0.081], [0.8, 1.15, 0.48])
            orb(0.006, .white, [x - 0.003, 0.299, 0.091])
            orb(0.018, .systemOrange, [x * 1.48, 0.265, 0.071], [1, 0.5, 0.2])
        }
        orb(0.009, dark, [0, 0.265, 0.09], [1, 0.65, 0.6])
        orb(0.04, gold, [-0.116, 0.16, 0], [0.55, 1, 0.65])
        orb(0.04, gold, [0.116, 0.18, 0], [0.55, 1, 0.65])
        orb(0.034, gold, [-0.05, 0.027, 0.015], [1, 0.6, 1.4])
        orb(0.034, gold, [0.05, 0.027, 0.015], [1, 0.6, 1.4])
        orb(0.04, .systemMint, [0.015, 0.386, 0.025], [0.95, 0.24, 0.45])
        return root
    }

    static func marker() -> Entity {
        let root = Entity()
        let material = UnlitMaterial(color: UIColor(red: 0.77, green: 1, blue: 0.58, alpha: 1))
        let center = ModelEntity(mesh: .generateSphere(radius: 0.018), materials: [material])
        root.addChild(center)
        for index in 0..<8 {
            let angle = Float(index) * .pi / 4
            let spark = ModelEntity(mesh: .generateSphere(radius: 0.005), materials: [material])
            spark.position = [cos(angle) * 0.065, sin(angle) * 0.065, 0]
            root.addChild(spark)
        }
        return root
    }
}
