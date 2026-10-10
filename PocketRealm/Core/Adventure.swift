import Foundation

struct Adventure {
    enum Phase: Equatable { case scanning, planning, restoring, ready, exploring, revealed, questing, returning, playing, complete }
    private(set) var phase: Phase = .scanning
    private(set) var challenge: QuestGame?
    mutating func finishScan() { if phase == .scanning { phase = .planning } }
    mutating func beginRestoring() { if phase == .scanning { phase = .restoring } }
    @discardableResult mutating func restorePlan(aligned: Bool, challenge: QuestGame? = nil) -> Bool {
        guard phase == .restoring, aligned else { return false }
        self.challenge = challenge; phase = .ready
        return true
    }
    mutating func acceptPlan(challenge: QuestGame? = nil) {
        if phase == .planning { self.challenge = challenge; phase = .ready }
    }
    mutating func beginExploring() { if phase == .ready { phase = .exploring } }
    @discardableResult mutating func reveal(trackingReady: Bool, proximitySatisfied: Bool) -> Bool {
        guard phase == .exploring, trackingReady, proximitySatisfied else { return false }
        phase = .revealed
        return true
    }
    @discardableResult mutating func talk(trackingReady: Bool, inReach: Bool) -> Bool {
        guard phase == .revealed, trackingReady, inReach else { return false }
        phase = .questing
        return true
    }
    @discardableResult mutating func collect(trackingReady: Bool, inReach: Bool) -> Bool {
        guard phase == .questing, trackingReady, inReach else { return false }
        phase = .returning
        return true
    }
    @discardableResult mutating func finishQuest(trackingReady: Bool, inReach: Bool) -> Bool {
        guard trackingReady, inReach else { return false }
        if challenge != nil {
            guard phase == .playing, challenge?.solved == true else { return false }
        } else { guard phase == .returning else { return false } }
        phase = .complete
        return true
    }
    @discardableResult mutating func beginChallenge(trackingReady: Bool, inReach: Bool) -> Bool {
        guard phase == .returning, challenge != nil, trackingReady, inReach else { return false }
        phase = .playing
        return true
    }
    @discardableResult mutating func playChallenge(_ action: QuestAction, trackingReady: Bool, inReach: Bool) -> QuestOutcome {
        guard phase == .playing, trackingReady, inReach else { return .ignored }
        return challenge?.perform(action) ?? .ignored
    }
    mutating func advanceChallenge(delta: Double, available: Bool) {
        guard phase == .playing, challenge?.memoryStage == .showing else { return }
        challenge?.advancePlayback(delta: delta, available: available)
    }
}

/// Counts distinct viewing directions; waving back and forth cannot complete a sweep.
struct ScanCoverage {
    private(set) var bins: Set<Int> = []
    var fraction: Double { Double(bins.count) / 24 }
    var complete: Bool { bins.count == 24 }
    mutating func observe(yaw: Double, trackingReady: Bool) {
        guard trackingReady, yaw.isFinite else { return }
        let turn = 2 * Double.pi
        let wrapped = (yaw.truncatingRemainder(dividingBy: turn) + turn).truncatingRemainder(dividingBy: turn)
        bins.insert(min(23, Int(wrapped / turn * 24)))
    }
}

/// First leave the spot, then approach it steadily with valid tracking.
struct ProximityGate {
    private(set) var armed = false
    private var enteredAt: Double?
    mutating func update(distance: Float, timestamp: Double, valid: Bool) -> Bool {
        guard valid, distance.isFinite, timestamp.isFinite else { enteredAt = nil; return false }
        if distance >= 1.8 { armed = true }
        guard armed, distance <= 1.4 else { enteredAt = nil; return false }
        if let enteredAt { return timestamp - enteredAt >= 0.8 }
        enteredAt = timestamp
        return false
    }
}

struct RoomCandidate: Codable, Identifiable {
    let id: String
    let category: String
    let dimensions: [Float]
    let position: [Float]
    let distance: Float
}

struct EncounterPlan: Codable {
    let objectID: String
    let hint: String
    let greeting: String
    var room: RoomUnderstanding? = nil
    var challenge: QuestPlan? = nil
    func validate(against candidates: [RoomCandidate]) throws {
        guard candidates.contains(where: { $0.id == objectID }),
              !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hint.count <= 240, greeting.count <= 400 else { throw PlanError.invalidPlan }
    }
    func validateRoom(against candidates: [RoomCandidate], surfaces: [RoomSurfaceContext]) throws {
        try validate(against: candidates)
        guard let room else {
            throw PlanError.server("Your server needs the room-understanding update. Restart server/server.py on your Mac, then try again.")
        }
        try room.validate(candidates: candidates, surfaces: surfaces, friendID: objectID)
    }
}

enum PlanError: LocalizedError {
    case invalidPlan, invalidURL, server(String)
    var errorDescription: String? {
        switch self {
        case .invalidPlan: return "The adventure didn't match this scan. Try asking Gemini again."
        case .invalidURL: return "Set your adventure server address in Connection settings."
        case .server(let message): return message
        }
    }
}
