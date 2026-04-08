// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PRSieve",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PRSieve",
            path: "Sources/PRSieve"
        ),
    ]
)
