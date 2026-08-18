// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadAloudConfig",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "readaloud-config", targets: ["ReadAloudConfig"])
    ],
    targets: [
        .executableTarget(name: "ReadAloudConfig")
    ]
)
