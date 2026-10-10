import Foundation

struct AdventureClient {
    struct Request: Encodable {
        let candidates: [RoomCandidate]
        let photos: [ScanPhoto]
        let friend: RealmFriend
        let planningVersion = 3
        let questVersion = 1
        let roomContext: RoomScanContext
    }
    static func endpoint(_ address: String) throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw PlanError.invalidURL }
        return url.appendingPathComponent("plan")
    }
    static func plan(address: String, candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend, context: RoomScanContext) async throws -> EncounterPlan {
        var request = URLRequest(url: try endpoint(address))
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(candidates: candidates, photos: photos, friend: friend, roomContext: context))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "The adventure server didn't respond. Check the address and Wi-Fi, then retry."
            throw PlanError.server(message)
        }
        let plan = try JSONDecoder().decode(EncounterPlan.self, from: data)
        try plan.validateRoom(against: candidates, surfaces: context.surfaces)
        try plan.challenge?.validate(for: friend)
        return plan
    }
}
