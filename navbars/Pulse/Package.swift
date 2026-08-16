// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Pulse", path: "Sources/Pulse")
    ]
)
