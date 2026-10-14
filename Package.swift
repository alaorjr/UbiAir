// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UbiAir",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThinQCore", targets: ["ThinQCore"]),
        .executable(name: "UbiAirMenuBar", targets: ["UbiAirMenuBar"])
    ],
    targets: [
        .target(name: "ThinQCore"),
        .executableTarget(name: "UbiAirMenuBar", dependencies: ["ThinQCore"]),
        .testTarget(name: "ThinQCoreTests", dependencies: ["ThinQCore"]),
        .testTarget(name: "UbiAirTests", dependencies: ["UbiAirMenuBar"])
    ]
)
