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
    static func endpoint(_ address: String, path: String = "plan") throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw PlanError.invalidURL }
        return url.appendingPathComponent(path)
    }
    /// Quick reachability check so a blocked network fails in seconds with a clear cause,
    /// instead of the plan upload hanging until the generic "request timed out".
    static func checkServer(address: String, drawingsRequired: Bool = false) async throws {
        let url = try endpoint(address, path: "health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            throw PlanError.server("Can't reach the server at \(url.host ?? address). Check that it's running and the address is correct. For a local server, connect both devices to the same Wi-Fi or hotspot.")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let health = try? JSONDecoder().decode(AdventureServerHealth.self, from: data) else {
            throw PlanError.server("This address didn't return a Pocket Realm server. Check Connection settings and try again.")
        }
        try health.validate(drawingsRequired: drawingsRequired)
    }
    static func plan(address: String, candidates: [RoomCandidate], photos: [ScanPhoto], friend: RealmFriend, context: RoomScanContext) async throws -> EncounterPlan {
        try await checkServer(address: address)
        var request = URLRequest(url: try endpoint(address))
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(candidates: candidates, photos: photos, friend: friend, roomContext: context))
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError where error.code == .timedOut {
            throw PlanError.server("The server got your scan but didn't answer in time. Check its terminal window for the reason, then retry.")
        }
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
