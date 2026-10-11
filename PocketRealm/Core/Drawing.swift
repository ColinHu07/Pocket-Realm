import Foundation

/// Planning and drawing generation are independent server capabilities.
struct AdventureServerHealth: Decodable {
    let geminiConfigured: Bool?
    var museConfigured: Bool? = nil
    let drawings: Bool?

    func validate(drawingsRequired: Bool) throws {
        if drawingsRequired {
            guard drawings == true else {
                throw PlanError.server("This server doesn't have a drawing workshop. Check the workshop address in Connection settings.")
            }
        } else if geminiConfigured != true && museConfigured != true {
            throw PlanError.server("The server is running but has no AI key. Add MUSE_API_KEY or GEMINI_API_KEY to server/.env and restart it.")
        }
    }
}

/// The server's view of one paper-drawing-to-3D job.
struct DrawingStatus: Decodable, Equatable {
    let id: String
    let status: String
    var ahead: Int? = nil
    var name: String? = nil
    var error: String? = nil
    var card: DrawingCard? = nil
}

/// Progress while a drawing becomes a companion or quest helper.
enum DrawingProgress: Equatable {
    case none
    case uploading
    case queued(ahead: Int)
    case building
    case ready(name: String)
    case failed(String)

    init(_ status: DrawingStatus) {
        switch status.status {
        case "queued": self = .queued(ahead: max(0, status.ahead ?? 0))
        case "working": self = .building
        case "ready": self = .ready(name: status.name ?? "drawing")
        default: self = .failed(status.error ?? "Couldn't turn this drawing into 3D. Try a bolder drawing.")
        }
    }

    var isWorking: Bool {
        switch self {
        case .uploading, .queued, .building: return true
        default: return false
        }
    }

    var readyName: String? {
        if case .ready(let name) = self { return name }
        return nil
    }

    var message: String {
        switch self {
        case .none: return "Draw something on paper to make a 3D companion or quest helper."
        case .uploading: return "Sending your drawing…"
        case .queued(let ahead): return ahead > 0 ? "In line for the 3D workshop (\(ahead) ahead)…" : "Opening the 3D workshop…"
        case .building: return "Your drawing is taking shape in the workshop. You can keep exploring."
        case .ready(let name): return "Ready! Your \(name) can join the adventure."
        case .failed(let reason): return reason
        }
    }
}
