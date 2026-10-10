import XCTest
import simd
@testable import AdventureCore

final class FriendAttentionTests: XCTestCase {
    private func view(_ position: SIMD3<Float>, looking: Bool = true) -> FriendAttention.View {
        .init(cameraPosition: position, isLooking: looking)
    }

    private func settle(_ attention: inout FriendAttention, at view: FriendAttention.View?, seconds: Int = 4) {
        for _ in 0..<(seconds * 60) { attention.update(delta: 1.0 / 60, view: view) }
    }

    func testCloseVisibleCameraTurnsCharacterWithoutUsingCameraHeight() {
        var low = FriendAttention(), high = FriendAttention()
        settle(&low, at: view([1, 0.4, 0]))
        settle(&high, at: view([1, 1.8, 0]))
        XCTAssertTrue(low.isAttentive)
        XCTAssertEqual(low.yaw, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(low.yaw, high.yaw)
        var distant = FriendAttention()
        settle(&distant, at: view([3, 0.5, 0]))
        XCTAssertFalse(distant.isAttentive)
        XCTAssertEqual(distant.yaw, 0)
    }

    func testLookingAwayHoldsBrieflyThenSmoothlyReturnsToIdle() {
        var attention = FriendAttention()
        settle(&attention, at: view([1, 1, 0]))
        let heading = attention.yaw
        for _ in 0..<12 { attention.update(delta: 1.0 / 60, view: view([-1,1,0], looking: false)) }
        XCTAssertTrue(attention.isAttentive)
        XCTAssertEqual(attention.yaw, heading, accuracy: 0.001)
        for _ in 0..<30 { attention.update(delta: 1.0 / 60, view: view([-1,1,0], looking: false)) }
        XCTAssertFalse(attention.isAttentive)
        XCTAssertGreaterThan(attention.yaw, 0)
        XCTAssertLessThan(attention.yaw, heading)
        settle(&attention, at: nil)
        XCTAssertEqual(attention.yaw, 0, accuracy: 0.001)
    }

    func testDistanceHysteresisPreventsRepeatedActivationAtBoundary() {
        var attention = FriendAttention()
        settle(&attention, at: view([2.1, 1, 0]))
        XCTAssertFalse(attention.isAttentive)
        settle(&attention, at: view([1.9, 1, 0]))
        XCTAssertTrue(attention.isAttentive)
        settle(&attention, at: view([2.2, 1, 0]))
        XCTAssertTrue(attention.isAttentive)
        settle(&attention, at: view([2.6, 1, 0]))
        XCTAssertFalse(attention.isAttentive)
        XCTAssertEqual(attention.yaw, 0, accuracy: 0.001)
    }

    func testTurnsAcrossBackUsingShortestArcAndRateLimit() {
        var attention = FriendAttention()
        settle(&attention, at: view([0.02, 1, -1]))
        let before = attention.yaw
        attention.update(delta: 1.0 / 60, view: view([-0.02, 1, -1]))
        let step = atan2(sin(attention.yaw-before), cos(attention.yaw-before))
        XCTAssertGreaterThan(step, 0)
        XCTAssertLessThanOrEqual(abs(step), .pi / 60)
        settle(&attention, at: view([-0.02, 1, -1]))
        XCTAssertEqual(attention.yaw, atan2(-0.02, -1), accuracy: 0.001)
    }

    func testInvalidInputAndOverheadCameraCannotProduceSpinsOrNonfinitePose() {
        for point: SIMD3<Float> in [[0, 1.5, 0], [.nan,1,0], [0,.infinity,1], [1,1,.nan]] {
            var attention = FriendAttention()
            settle(&attention, at: view(point))
            XCTAssertFalse(attention.isAttentive)
            XCTAssertEqual(attention.yaw, 0)
        }
        var attention = FriendAttention()
        for delta in [0.0, -1, .infinity, .nan] {
            attention.update(delta: delta, view: view([1,1,0]))
            XCTAssertEqual(attention.yaw, 0)
        }
    }

    func testReducedMotionStillFacesViewerWithSlowerBoundedTurn() {
        var attention = FriendAttention()
        attention.update(delta: 1.0 / 60, view: view([1,1,0]), reducedMotion: true)
        XCTAssertGreaterThan(attention.yaw, 0)
        XCTAssertLessThanOrEqual(attention.yaw, .pi / 120 + 0.000001)
        for _ in 0..<300 { attention.update(delta: 1.0 / 60, view: view([1,1,0]), reducedMotion: true) }
        XCTAssertEqual(attention.yaw, .pi / 2, accuracy: 0.001)
    }

    func testTurningIsConsistentAcrossFrameRates() {
        var slow = FriendAttention(), fast = FriendAttention()
        for _ in 0..<90 { slow.update(delta: 1.0 / 30, view: view([-1,1,0])) }
        for _ in 0..<180 { fast.update(delta: 1.0 / 60, view: view([-1,1,0])) }
        XCTAssertEqual(slow.yaw, fast.yaw, accuracy: 0.001)
    }
}
