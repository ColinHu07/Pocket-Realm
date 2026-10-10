import Foundation
import simd

/// Camera attention is independent of authored reactions and never moves the
/// character off its support. All positions/yaw are relative to that support.
struct FriendAttention {
    struct View {
        let cameraPosition: SIMD3<Float>
        let isLooking: Bool
    }

    static let approachDistance: Float = 2
    static let departureDistance: Float = 2.4
    static let lookAwayDelay: Float = 0.55
    private(set) var isAttentive = false
    private(set) var yaw: Float = 0
    private var targetYaw: Float = 0
    private var timeAway: Float = 0

    @discardableResult
    mutating func update(delta: Double, view: View?, reducedMotion: Bool = false) -> Float {
        let step = Float(delta.isFinite ? min(max(delta, 0), 0.1) : 0)
        guard step > 0 else { return yaw }
        var looking = false
        if let view, view.isLooking, view.cameraPosition.x.isFinite,
           view.cameraPosition.y.isFinite, view.cameraPosition.z.isFinite {
            let offset = SIMD2(view.cameraPosition.x, view.cameraPosition.z)
            let distance = simd_length(offset)
            // Directly overhead has no stable horizontal heading.
            if distance >= 0.08 && distance <= (isAttentive ? Self.departureDistance : Self.approachDistance) {
                looking = true
                isAttentive = true
                timeAway = 0
                targetYaw = atan2(offset.x, offset.y) // Imported faces point along +Z.
            }
        }
        if !looking {
            timeAway = min(Self.lookAwayDelay, timeAway + step)
            if timeAway >= Self.lookAwayDelay {
                isAttentive = false
                targetYaw = 0
            }
        }
        // Follow the shortest arc, with an angular speed limit and a soft finish.
        // Brief camera jitter holds the last heading instead of toggling idle.
        let difference = Self.wrapped(targetYaw - yaw)
        let gain: Float = isAttentive && !reducedMotion ? 6 : 3
        let speed: Float = reducedMotion ? .pi / 2 : (isAttentive ? .pi : .pi / 2)
        let turn = difference * (1 - exp(-gain * step))
        yaw = Self.wrapped(yaw + min(speed * step, max(-speed * step, turn)))
        return yaw
    }

    private static func wrapped(_ angle: Float) -> Float { atan2(sin(angle), cos(angle)) }
}
