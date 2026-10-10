import Foundation

enum PlanningProvider: String, CaseIterable, Identifiable {
    case muse, gemini
    var id: String { rawValue }
    var name: String { self == .muse ? "Muse" : "Gemini" }
    var company: String { self == .muse ? "Meta" : "Google" }
    static func saved(_ value: String?) -> Self { value.flatMap(Self.init(rawValue:)) ?? .muse }
}

enum PlanningConnectionState: Equatable {
    case needsKey, saved, checking(Date), connected(Date), failed(String)
    var isChecking: Bool { if case .checking = self { return true }; return false }
}

/// Explicit routing: one selected provider, one request, no automatic cross-provider fallback.
struct PlanningClient {
    var provider: PlanningProvider = .muse
    var muse = MuseClient()
    var gemini = GeminiClient()

    var modelName: String { provider == .muse ? muse.model.name : gemini.model.name }
    var connectionTimeout: TimeInterval {
        provider == .muse ? MuseClient.connectionTimeout : GeminiClient.connectionTimeout
    }

    func plan(key: String, candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend,
              context: RoomScanContext) async throws -> EncounterPlan {
        switch provider {
        case .muse: return try await muse.plan(key: key, candidates: candidates, photos: photos, friend: friend, context: context)
        case .gemini: return try await gemini.plan(key: key, candidates: candidates, photos: photos, friend: friend, context: context)
        }
    }

    func test(key: String) async throws {
        switch provider {
        case .muse: try await muse.test(key: key)
        case .gemini: try await gemini.test(key: key)
        }
    }
}
