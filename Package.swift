// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LGThinQ",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThinQCore", targets: ["ThinQCore"]),
        .executable(name: "LGThinQMenuBar", targets: ["LGThinQMenuBar"])
    ],
    targets: [
        .target(name: "ThinQCore"),
        .executableTarget(name: "LGThinQMenuBar", dependencies: ["ThinQCore"]),
        .testTarget(name: "ThinQCoreTests", dependencies: ["ThinQCore"])
    ]
)
