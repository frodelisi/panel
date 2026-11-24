// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Panel",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Panel", path: "Sources/Panel")
    ]
)
