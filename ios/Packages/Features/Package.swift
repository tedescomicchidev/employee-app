// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Features",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "Features", targets: ["Features"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "Features", dependencies: ["Core"], resources: [.process("Resources")]),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"]),
    ]
)
