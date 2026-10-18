// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Core",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Core", targets: ["Core"])],
    targets: [
        .target(name: "Core", resources: [.process("Resources")]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
