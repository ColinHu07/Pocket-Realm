import Foundation

enum PlanningProvider: String, CaseIterable, Identifiable {
    /// `server`: the Pocket Realm server holds the keys (Muse first, Gemini as backup); nothing on the phone.
    case server, muse, gemini
    var id: String { rawValue }
    var name: String {
        switch self {
        case .server: return "Pocket Realm server"
        case .muse: return "Muse"
        case .gemini: return "Gemini"
        }
    }
    var company: String {
        switch self {
        case .server: return "your Pocket Realm server"
        case .muse: return "Meta"
        case .gemini: return "Google"
        }
    }
    var needsKey: Bool { self != .server }
    static func saved(_ value: String?) -> Self { value.flatMap(Self.init(rawValue:)) ?? .server }
}

/// How the app reaches the Pocket Realm server; supplied by the app target, which owns networking.
struct ServerPlanning {
    var plan: (([RoomCandidate], [ScanPhoto], RealmFriend, RoomScanContext) async throws -> EncounterPlan)?
    var test: (() async throws -> Void)?
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
    var server = ServerPlanning()

    var modelName: String {
        switch provider {
        case .server: return "Muse Spark on your server"
        case .muse: return muse.model.name
        case .gemini: return gemini.model.name
        }
    }
    var connectionTimeout: TimeInterval {
        switch provider {
        case .server: return 75
        case .muse: return MuseClient.connectionTimeout
        case .gemini: return GeminiClient.connectionTimeout
        }
    }

    func plan(key: String, candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend,
              context: RoomScanContext) async throws -> EncounterPlan {
        switch provider {
        case .server:
            guard let plan = server.plan else { throw PlanError.invalidURL }
            return try await plan(candidates, photos, friend, context)
        case .muse: return try await muse.plan(key: key, candidates: candidates, photos: photos, friend: friend, context: context)
        case .gemini: return try await gemini.plan(key: key, candidates: candidates, photos: photos, friend: friend, context: context)
        }
    }

    func test(key: String) async throws {
        switch provider {
        case .server:
            guard let test = server.test else { throw PlanError.invalidURL }
            try await test()
        case .muse: try await muse.test(key: key)
        case .gemini: try await gemini.test(key: key)
        }
    }
}
