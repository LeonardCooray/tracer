// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tracer",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "TracerCore"),
        .executableTarget(name: "Tracer", dependencies: ["TracerCore"]),
        .testTarget(name: "TracerCoreTests", dependencies: ["TracerCore"]),
    ]
)
