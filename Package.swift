// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AdventureCore",
    products: [.library(name: "AdventureCore", targets: ["AdventureCore"])],
    targets: [
        .target(name: "AdventureCore", path: "PocketRealm/Core"),
        .testTarget(name: "AdventureCoreTests", dependencies: ["AdventureCore"], path: "Tests/AdventureCoreTests")
    ]
)
