// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fener",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "fener", path: "Sources/Fener"),
        .testTarget(name: "FenerTests", dependencies: ["fener"]),
    ]
)
