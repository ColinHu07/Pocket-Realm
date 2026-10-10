// swiftc RealmFriend.swift FriendMotion.swift this-file.swift -o build/export-motion-preview
import Foundation
@main struct ExportMotionPreview {
    static func main() throws {
        let fps = 12
        var motions = RealmFriend.allCases.map { FriendMotion(friend: $0) }
        let cues: [Int: FriendReaction] = [18: .greeting, 48: .pet, 74: .play, 116: .celebrate]
        var frames: [[String: Any]] = []
        for frame in 0..<168 {
            var friends: [String: Any] = [:]
            for index in motions.indices {
                if let reaction = cues[frame] { motions[index].trigger(reaction) }
                let p = motions[index].update(delta: 1.0/Double(fps))
                func array(_ v: SIMD3<Float>) -> [Float] { [v.x,v.y,v.z] }
                friends[RealmFriend.allCases[index].name] = [
                    "scale": array(p.scale), "position": array(p.position), "rotation": array(p.rotation),
                    "eyes": p.eyes, "mouth": p.mouth, "appendage": p.appendage, "tail": p.tail,
                    "effect": p.effect, "effectProgress": p.effectProgress,
                    "reaction": motions[index].reaction?.rawValue ?? "idle"]
            }
            frames.append(["frame": frame+1, "friends": friends])
        }
        let data = try JSONSerialization.data(withJSONObject: ["fps": fps, "frames": frames], options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
