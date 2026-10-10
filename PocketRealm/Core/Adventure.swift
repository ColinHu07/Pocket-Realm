import Foundation

struct Adventure {
    enum Phase: Equatable { case scanning, planning, exploring, revealed, complete }
    private(set) var phase: Phase = .scanning
    mutating func finishScan() { if phase == .scanning { phase = .planning } }
    mutating func acceptPlan() { if phase == .planning { phase = .exploring } }
    @discardableResult mutating func reveal(trackingReady: Bool, proximitySatisfied: Bool) -> Bool {
        guard phase == .exploring, trackingReady, proximitySatisfied else { return false }
        phase = .revealed
        return true
    }
    @discardableResult mutating func talk(trackingReady: Bool, inReach: Bool) -> Bool {
        guard phase == .revealed, trackingReady, inReach else { return false }
        phase = .complete
        return true
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
    func validate(against candidates: [RoomCandidate]) throws {
        guard candidates.contains(where: { $0.id == objectID }),
              !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hint.count <= 240, greeting.count <= 400 else { throw PlanError.invalidPlan }
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
