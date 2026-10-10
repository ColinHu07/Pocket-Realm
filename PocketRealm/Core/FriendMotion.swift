import Foundation

/// A deterministic pose sampler shared by AR, the preview, and animation validation.
/// Every pose is absolute, so repeated interactions cannot accumulate transform drift.
enum FriendReaction: String, CaseIterable {
    case appear, greeting, pet, celebrate, chat, play
    var duration: Float {
        switch self {
        case .appear: return 1.1
        case .greeting: return 2.2
        case .pet: return 1.8
        case .celebrate: return 3.4
        case .chat: return 1.7
        case .play: return 3.2
        }
    }
}

struct FriendPose {
    var scale = SIMD3<Float>(repeating: 1)
    var position = SIMD3<Float>.zero
    var rotation = SIMD3<Float>.zero
    var eyes: Float = 1
    var mouth: Float = 1
    var appendage: Float = 0
    var tail: Float = 0
    var effect: Float = 0
    var effectProgress: Float = 0
}

struct FriendMotion {
    let friend: RealmFriend
    private(set) var time: Float = 0
    private(set) var reaction: FriendReaction? = .appear
    private(set) var reactionAge: Float = 0
    private var blendFrom = FriendPose()
    private var blendAge: Float = 1
    private var lastPose = FriendPose(scale: .init(repeating: 0.01))

    init(friend: RealmFriend) { self.friend = friend }

    /// Repeated taps have a brief cooldown; an earned celebration finishes before another action.
    @discardableResult mutating func trigger(_ next: FriendReaction) -> Bool {
        if reaction == .celebrate && reactionAge < FriendReaction.celebrate.duration { return false }
        if reaction == next && reactionAge < 0.35 { return false }
        blendFrom = lastPose
        blendAge = 0
        reaction = next
        reactionAge = 0
        return true
    }

    mutating func update(delta: Double, speaking: Bool = false, reducedMotion: Bool = false) -> FriendPose {
        let step = Float(delta.isFinite ? min(max(delta, 0), 0.1) : 0)
        time += step; reactionAge += step; blendAge += step
        if let reaction, reactionAge >= reaction.duration { self.reaction = nil }
        var pose = Self.sample(friend: friend, time: time, reaction: reaction, age: reactionAge,
                               speaking: speaking, reducedMotion: reducedMotion)
        if blendAge < 0.16 {
            let f = Self.smooth(blendAge / 0.16)
            pose.scale = blendFrom.scale + (pose.scale - blendFrom.scale) * f
            pose.position = blendFrom.position + (pose.position - blendFrom.position) * f
            for axis in 0..<3 {
                let difference = pose.rotation[axis] - blendFrom.rotation[axis]
                pose.rotation[axis] = blendFrom.rotation[axis] + atan2(sin(difference), cos(difference)) * f
            }
            pose.eyes = blendFrom.eyes + (pose.eyes - blendFrom.eyes) * f
        }
        lastPose = pose
        return pose
    }

    static func smooth(_ x: Float) -> Float {
        let t = min(1, max(0, x)); return t * t * (3 - 2 * t)
    }

    static func sample(friend: RealmFriend, time: Float, reaction: FriendReaction?, age: Float,
                       speaking: Bool = false, reducedMotion: Bool = false) -> FriendPose {
        var p = FriendPose()
        let t = time * friend.tempo
        let breath = sin(t * 2) * (reducedMotion ? 0.002 : 0.010)
        p.scale = [1 - breath * 0.4, 1 + breath, 1 - breath * 0.4]
        p.position.y = reducedMotion ? 0 : sin(t * 2.2) * (friend == .glimlo ? 0.017 : 0.004)
        p.rotation.z = reducedMotion ? 0 : sin(t * 1.2) * 0.018
        p.appendage = reducedMotion ? 0 : sin(t * (friend == .glimlo ? 9 : 2.4)) * (friend == .glimlo ? 0.26 : 0.07)
        p.tail = reducedMotion ? 0 : sin(t * 2.8) * 0.16
        let phase = (time + Float(RealmFriend.allCases.firstIndex(of: friend) ?? 0) * 0.61).truncatingRemainder(dividingBy: 4.7)
        if phase < 0.20 { p.eyes = 1 - 0.94 * pow(sin(.pi * phase / 0.20), 2) }
        if speaking { p.mouth = 1 + 0.35 * pow(sin(time * 13), 2); p.rotation.x += sin(time * 5) * (reducedMotion ? 0 : 0.02) }
        guard let reaction else { return p }
        let u = min(1, max(0, age / reaction.duration))
        let envelope = smooth(u / 0.15) * smooth((1 - u) / 0.22)
        if reducedMotion {
            p.eyes = min(p.eyes, 1 - envelope * 0.45)
            p.scale.y += envelope * 0.018
            return p
        }
        switch reaction {
        case .appear:
            let grow = max(0.01, smooth(u / 0.78))
            p.scale *= grow
            p.scale.y *= 1 + sin(u * .pi * 2) * 0.07 * (1-u)
            p.position.y -= (1-grow) * 0.04
        case .greeting:
            p.rotation.x += sin(u * .pi * 4) * envelope * 0.10
            p.rotation.z += envelope * 0.045
            p.appendage += sin(u * .pi * 6) * envelope * 0.20
            p.tail += sin(u * .pi * 8) * envelope * 0.30
        case .pet:
            p.rotation.z += envelope * 0.14
            p.rotation.x -= envelope * 0.06
            p.scale.y -= envelope * 0.075
            p.scale.x += envelope * 0.04
            p.scale.z += envelope * 0.04
            p.eyes = min(p.eyes, 1 - envelope * 0.78)
            p.mouth += envelope * 0.15
            p.appendage += sin(u * .pi * 8) * envelope * 0.16
            p.tail += sin(u * .pi * 10) * envelope * 0.35
            p.effect = envelope
            p.effectProgress = u
        case .celebrate, .play:
            let jumps: Float = friend == .pebblin ? 1 : (friend == .nibbi ? 3 : 2)
            let hop = pow(sin(u * .pi * jumps), 2) * envelope
            let height: Float = friend == .pebblin ? 0.025 : (friend == .glimlo ? 0.09 : 0.075)
            p.position.y += hop * height
            p.scale.y += sin(u * .pi * jumps * 2) * envelope * 0.07
            p.scale.x -= sin(u * .pi * jumps * 2) * envelope * 0.03
            p.rotation.z += sin(u * .pi * 6) * envelope * (friend == .pebblin ? 0.06 : 0.13)
            // A full eased turn ends at the same orientation; the tail follows through.
            if friend == .cindlet || (reaction == .celebrate && friend == .glimlo) {
                p.rotation.y = 2 * .pi * smooth((u-0.18)/0.62)
            }
            p.appendage += sin(u * .pi * 12) * envelope * 0.30
            p.tail += sin(u * .pi * 12) * envelope * 0.42
            p.eyes = min(p.eyes, 1 - hop * 0.4)
            if reaction == .celebrate { p.effect = envelope; p.effectProgress = u }
        case .chat:
            p.rotation.x += sin(u * .pi * 4) * envelope * 0.055
            p.rotation.z += envelope * 0.07
            p.mouth += pow(sin(u * .pi * 10), 2) * envelope * 0.3
        }
        return p
    }
}
