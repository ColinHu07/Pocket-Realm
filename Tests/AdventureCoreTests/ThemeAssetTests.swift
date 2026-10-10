import Foundation
import XCTest
@testable import AdventureCore

final class ThemeAssetTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    // Asset names and runtime budgets must agree with the actual Blender exports.
    func testThemeCatalogMatchesExportManifestsAndBundledFiles() throws {
        struct Stats: Decodable { let triangles: Int; let materials: Int; let bytes: Int }
        let manifest = try JSONDecoder().decode([String: Stats].self,
            from: Data(contentsOf: root.appendingPathComponent("Art/Themes/manifest.json")))
        var referenced = Set<String>()
        for theme in [RealmTheme.reef, .cavern, .woodland] {
            let assets = theme.assets(palette: .forest)
            XCTAssertEqual(assets.count, 3)
            for asset in assets {
                XCTAssertTrue(referenced.insert(asset.name).inserted)
                let stats = try XCTUnwrap(manifest[asset.name])
                XCTAssertLessThanOrEqual(stats.triangles, asset.triangles)
                XCTAssertLessThanOrEqual(stats.materials, 4)
                let url = root.appendingPathComponent("PocketRealm/Resources/\(asset.directory)/\(asset.name).usdz")
                XCTAssertEqual(try Data(contentsOf: url).count, stats.bytes)
            }
            let preview = try XCTUnwrap(theme.previewImage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(
                "PocketRealm/Resources/Assets.xcassets/\(preview).imageset/preview.png").path))
        }
        XCTAssertEqual(referenced, Set(manifest.keys))
    }

    func testSavedThemeIDsRemainCompatibleAndRoundTrip() throws {
        for theme in RealmTheme.allCases {
            XCTAssertEqual(try JSONDecoder().decode(RealmTheme.self, from: JSONEncoder().encode(theme)), theme)
        }
        XCTAssertEqual(try JSONDecoder().decode(RealmTheme.self, from: Data("\"jungle\"".utf8)), .jungle)
        XCTAssertEqual(try JSONDecoder().decode(RealmTheme.self, from: Data("\"original\"".utf8)), .original)
        XCTAssertTrue(RealmTheme.original.assets(palette: .forest).isEmpty)
        for theme in [RealmTheme.reef, .cavern, .woodland] {
            XCTAssertEqual(theme.assets(palette: .forest).map(\.name), theme.assets(palette: .tropical).map(\.name))
        }
    }
}
