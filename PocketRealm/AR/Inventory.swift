import Foundation
import UIKit

/// One finished drawing: its game card, 3D model, and the photo it came from.
struct Creation: Codable, Identifiable, Equatable {
    let id: String
    let card: DrawingCard
    let made: Date

    var modelURL: URL { Inventory.folder.appendingPathComponent("\(id).usdz") }
    var photoURL: URL { Inventory.folder.appendingPathComponent("\(id).jpg") }
    var photo: UIImage? { UIImage(contentsOfFile: photoURL.path) }
}

/// Everything the player has drawn, kept on the phone so it can be reused in later quests.
enum Inventory {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inventory", isDirectory: true)
    }
    private static var listURL: URL { folder.appendingPathComponent("inventory.json") }

    static func load() -> [Creation] {
        guard let data = try? Data(contentsOf: listURL),
              let items = try? JSONDecoder().decode([Creation].self, from: data) else { return [] }
        return items.filter { FileManager.default.fileExists(atPath: $0.modelURL.path) }
    }

    /// Moves the downloaded model into the inventory and records it, newest first.
    static func add(id: String, card: DrawingCard, model: URL, photo: UIImage?, to items: [Creation]) throws -> [Creation] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let creation = Creation(id: id, card: card, made: Date())
        try? FileManager.default.removeItem(at: creation.modelURL)
        try FileManager.default.moveItem(at: model, to: creation.modelURL)
        if let photo, let jpeg = DrawingWorkshop.jpeg(from: photo, maxDimension: 240) {
            try? jpeg.write(to: creation.photoURL, options: .atomic)
        }
        let updated = [creation] + items.filter { $0.id != id }
        try JSONEncoder().encode(updated).write(to: listURL, options: .atomic)
        return updated
    }
}
