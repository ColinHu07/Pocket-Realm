import Foundation

/// The server's view of one paper-drawing-to-3D job.
struct DrawingStatus: Decodable, Equatable {
    let id: String
    let status: String
    var ahead: Int? = nil
    var name: String? = nil
    var error: String? = nil
    var card: DrawingCard? = nil
}

/// Where the player's drawing is on its way to becoming the quest keepsake.
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
        case .none: return "Draw something on paper. Codex and Blender turn it into the 3D keepsake you'll find."
        case .uploading: return "Sending your drawing…"
        case .queued(let ahead): return ahead > 0 ? "In line for the 3D workshop (\(ahead) ahead)…" : "Opening the 3D workshop…"
        case .building: return "Codex is sculpting it in Blender. About a minute. You can start scanning."
        case .ready(let name): return "Ready! Your \(name) will be the keepsake you find."
        case .failed(let reason): return reason
        }
    }
}
