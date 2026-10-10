import XCTest
@testable import AdventureCore

final class FriendMotionTests: XCTestCase {
    func testEveryFriendHasDistinctQuestAndSavedIdentity() throws {
        XCTAssertEqual(RealmFriend.allCases.count, 6)
        XCTAssertEqual(Set(RealmFriend.allCases.map(\.reward)).count, 6)
        XCTAssertEqual(Set(RealmFriend.allCases.map(\.itemName)).count, 6)
        for friend in RealmFriend.allCases {
            XCTAssertEqual(try JSONDecoder().decode(RealmFriend.self, from: JSONEncoder().encode(friend)), friend)
            XCTAssertTrue(friend.questRequest.contains(friend.itemName))
            XCTAssertFalse(friend.petReaction.isEmpty)
            XCTAssertFalse(friend.playReaction.isEmpty)
        }
    }

    func testAllReactionFramesAreFiniteAndBounded() {
        for friend in RealmFriend.allCases {
            for reaction in FriendReaction.allCases {
                var motion = FriendMotion(friend: friend)
                _ = motion.trigger(reaction)
                for _ in 0..<300 {
                    let pose = motion.update(delta: 1.0/60, speaking: true)
                    for value in [pose.scale.x, pose.scale.y, pose.scale.z] {
                        XCTAssertTrue(value.isFinite && value >= 0.005 && value < 1.3, "\(friend) \(reaction)")
                    }
                    for value in [pose.position.x, pose.position.y, pose.position.z, pose.rotation.x, pose.rotation.y, pose.rotation.z, pose.appendage, pose.tail] {
                        XCTAssertTrue(value.isFinite)
                    }
                    XCTAssertLessThan(abs(pose.position.y), 0.2)
                    XCTAssertTrue((0.05...1.001).contains(pose.eyes))
                }
                XCTAssertNil(motion.reaction)
            }
        }
    }

    func testRepeatedTapsDoNotRestartReactionAndRewardCannotBeInterrupted() {
        var motion = FriendMotion(friend: .nibbi)
        XCTAssertTrue(motion.trigger(.pet))
        _ = motion.update(delta: 0.1)
        XCTAssertFalse(motion.trigger(.pet))
        XCTAssertTrue(motion.trigger(.celebrate))
        for _ in 0..<25 {
            _ = motion.update(delta: 0.1)
            XCTAssertFalse(motion.trigger(.pet))
            XCTAssertFalse(motion.trigger(.play))
        }
        for _ in 0..<12 { _ = motion.update(delta: 0.1) }
        XCTAssertTrue(motion.trigger(.pet))
    }

    func testInterruptingATurnBlendsAlongShortestArc() {
        var motion = FriendMotion(friend: .cindlet)
        _ = motion.trigger(.play)
        for _ in 0..<24 { _ = motion.update(delta: 0.1) }
        let before = motion.update(delta: 0)
        XCTAssertTrue(motion.trigger(.pet))
        let after = motion.update(delta: 1.0/60)
        let angle = after.rotation.y-before.rotation.y
        XCTAssertLessThan(abs(atan2(sin(angle),cos(angle))), 0.10)
        XCTAssertLessThan(abs(after.scale.y-before.scale.y), 0.02)
    }

    func testLongInteractionSessionReturnsToIdleWithoutDrift() {
        for friend in RealmFriend.allCases {
            var motion = FriendMotion(friend: friend)
            for _ in 0..<30 {
                _ = motion.trigger(.pet)
                for _ in 0..<24 { _ = motion.update(delta: 0.1) }
                _ = motion.trigger(.play)
                for _ in 0..<40 { _ = motion.update(delta: 0.1) }
            }
            let current = motion.update(delta: 0)
            let expected = FriendMotion.sample(friend: friend, time: motion.time, reaction: nil, age: 0)
            XCTAssertEqual(current.scale, expected.scale)
            XCTAssertEqual(current.position, expected.position)
            XCTAssertEqual(current.rotation, expected.rotation)
            XCTAssertEqual(current.effect, 0)
        }
    }

    func testReducedMotionRemovesHopsSpinsAndParticles() {
        for friend in RealmFriend.allCases {
            for reaction in FriendReaction.allCases {
                for frame in 0..<120 {
                    let pose = FriendMotion.sample(friend: friend, time: Float(frame)/30, reaction: reaction,
                                                   age: Float(frame)/30, reducedMotion: true)
                    XCTAssertEqual(pose.position, .zero)
                    XCTAssertEqual(pose.rotation, .zero)
                    XCTAssertEqual(pose.effect, 0)
                    XCTAssertEqual(pose.appendage, 0)
                    XCTAssertEqual(pose.tail, 0)
                }
            }
        }
    }

    func testPauseAndInvalidDeltasDoNotAdvanceMotion() {
        var motion = FriendMotion(friend: .bloopi)
        _ = motion.update(delta: 0.1)
        let time = motion.time
        let previous = motion.update(delta: 0)
        for delta in [0.0, -1, .nan, .infinity] {
            let pose = motion.update(delta: delta)
            XCTAssertEqual(motion.time, time)
            XCTAssertEqual(pose.position, previous.position)
        }
        _ = motion.update(delta: 50)
        XCTAssertEqual(motion.time-time, 0.1, accuracy: 0.0001)
    }
}
