import Foundation
import UIKit

/// Talks to the server's drawing workshop, where Codex and Blender turn a paper drawing into a USDZ.
enum DrawingWorkshop {
    static func jpeg(from image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.82)
    }

    static func submit(address: String, jpeg: Data, purpose: DrawingPurpose, challenge: String?, friend: String) async throws -> DrawingStatus {
        try await AdventureClient.checkServer(address: address, drawingsRequired: true)
        var request = URLRequest(url: try AdventureClient.endpoint(address, path: "drawings"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["image": jpeg.base64EncodedString(), "purpose": purpose.rawValue, "friend": friend]
        if let challenge { body["challenge"] = challenge }
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(URLSession.shared.data(for: request))
    }

    static func status(address: String, id: String) async throws -> DrawingStatus {
        var request = URLRequest(url: try AdventureClient.endpoint(address, path: "drawings/\(id)"))
        request.timeoutInterval = 15
        return try await decode(URLSession.shared.data(for: request))
    }

    static func download(address: String, id: String) async throws -> URL {
        var request = URLRequest(url: try AdventureClient.endpoint(address, path: "drawings/\(id)/model.usdz"))
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.starts(with: [0x50, 0x4B, 0x03, 0x04]) else {
            throw PlanError.server("Couldn't download your 3D drawing. Try drawing again.")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-\(id).usdz")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The server's render of the finished model; nil if it isn't available.
    static func preview(address: String, id: String) async -> Data? {
        guard var request = try? URLRequest(url: AdventureClient.endpoint(address, path: "drawings/\(id)/preview.png")) else { return nil }
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.starts(with: [0x89, 0x50, 0x4E, 0x47]), UIImage(data: data) != nil else { return nil }
        return data
    }

    private static func decode(_ result: (Data, URLResponse)) throws -> DrawingStatus {
        let (data, response) = result
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let error: String }
            throw PlanError.server((try? JSONDecoder().decode(Failure.self, from: data).error)
                ?? "The drawing workshop didn't respond. Try again.")
        }
        return try JSONDecoder().decode(DrawingStatus.self, from: data)
    }
}
