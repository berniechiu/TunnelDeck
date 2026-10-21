// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TunnelDeck",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TunnelCore", targets: ["TunnelCore"]),
        .executable(name: "TunnelDeck", targets: ["TunnelDeck"]),
    ],
    targets: [
        .target(name: "TunnelCore"),
        .executableTarget(name: "TunnelDeck", dependencies: ["TunnelCore"]),
        .testTarget(name: "TunnelCoreTests", dependencies: ["TunnelCore"]),
    ],
    swiftLanguageModes: [.v6]
)
