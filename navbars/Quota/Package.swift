// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Quota",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Quota", path: "Sources/Quota")
    ]
)
