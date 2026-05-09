// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "roadie",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RoadieCore", targets: ["RoadieCore"]),
        .library(name: "RoadieAX", targets: ["RoadieAX"]),
        .library(name: "RoadieDaemon", targets: ["RoadieDaemon"]),
        .library(name: "RoadieControlCenter", targets: ["RoadieControlCenter"]),
        .library(name: "RoadieStages", targets: ["RoadieStages"]),
        .library(name: "RoadieTiler", targets: ["RoadieTiler"]),
        .executable(name: "roadied", targets: ["roadied"]),
        .executable(name: "roadie", targets: ["roadie"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "RoadieCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit")
            ]
        ),
        .target(
            name: "RoadieAX",
            dependencies: ["RoadieCore"]
        ),
        .target(
            name: "RoadieDaemon",
            dependencies: ["RoadieAX", "RoadieStages", "RoadieTiler"]
        ),
        .target(
            name: "RoadieControlCenter",
            dependencies: ["RoadieDaemon"]
        ),
        .target(
            name: "RoadieStages",
            dependencies: ["RoadieCore"]
        ),
        .target(
            name: "RoadieTiler",
            dependencies: ["RoadieCore"]
        ),
        .executableTarget(
            name: "roadied",
            dependencies: ["RoadieDaemon"]
        ),
        .executableTarget(
            name: "roadie",
            dependencies: ["RoadieDaemon"]
        ),
        .testTarget(
            name: "RoadieDaemonTests",
            dependencies: ["RoadieDaemon"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "RoadieControlCenterTests",
            dependencies: ["RoadieControlCenter"]
        ),
        .testTarget(
            name: "RoadieStagesTests",
            dependencies: ["RoadieStages"]
        ),
        .testTarget(
            name: "RoadieTilerTests",
            dependencies: ["RoadieTiler"]
        ),
    ]
)
