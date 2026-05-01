// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "roadies",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "roadied", targets: ["roadied"]),
        .executable(name: "roadie", targets: ["roadie"]),
        .library(name: "RoadieCore", targets: ["RoadieCore"]),
        .library(name: "RoadieTiler", targets: ["RoadieTiler"]),
        .library(name: "RoadieStagePlugin", targets: ["RoadieStagePlugin"]),
        // SPEC-004 fx-framework — chargé runtime via dlopen, JAMAIS lié au daemon
        .library(name: "RoadieFXCore", type: .dynamic, targets: ["RoadieFXCore"]),
        // SPEC-008 RoadieBorders module opt-in
        .library(name: "RoadieBorders", type: .dynamic, targets: ["RoadieBorders"]),
    ],
    dependencies: [
        // TOML parser — justifié dans plan.md Complexity Tracking
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "RoadieCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/RoadieCore",
            linkerSettings: [
                // Framework privé SkyLight : nécessaire pour _SLPSSetFrontProcessWithOptions
                // et SLPSPostEventRecordTo (utilisés par WindowActivator pour
                // l'activation inter-app fiable sur Sonoma+/Sequoia/Tahoe).
                // Standard de l'industrie macOS WM (yabai, AeroSpace, Hammerspoon).
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks"]),
                .linkedFramework("SkyLight"),
            ]
        ),
        .target(
            name: "RoadieTiler",
            dependencies: ["RoadieCore"],
            path: "Sources/RoadieTiler"
        ),
        .target(
            name: "RoadieStagePlugin",
            dependencies: ["RoadieCore", "RoadieTiler"],
            path: "Sources/RoadieStagePlugin"
        ),
        .executableTarget(
            name: "roadied",
            dependencies: ["RoadieCore", "RoadieTiler", "RoadieStagePlugin"],
            path: "Sources/roadied"
        ),
        .executableTarget(
            name: "roadie",
            dependencies: ["RoadieCore"],
            path: "Sources/roadie"
        ),
        .testTarget(
            name: "RoadieCoreTests",
            dependencies: ["RoadieCore"],
            path: "Tests/RoadieCoreTests"
        ),
        .testTarget(
            name: "RoadieTilerTests",
            dependencies: ["RoadieTiler"],
            path: "Tests/RoadieTilerTests"
        ),
        .testTarget(
            name: "RoadieStagePluginTests",
            dependencies: ["RoadieStagePlugin"],
            path: "Tests/RoadieStagePluginTests"
        ),
        // SPEC-004 fx-framework target dynamic
        .target(
            name: "RoadieFXCore",
            dependencies: [
                "RoadieCore",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/RoadieFXCore"
        ),
        .testTarget(
            name: "RoadieFXCoreTests",
            dependencies: ["RoadieFXCore"],
            path: "Tests/RoadieFXCoreTests"
        ),
        // SPEC-008 RoadieBorders target
        .target(
            name: "RoadieBorders",
            dependencies: ["RoadieCore", "RoadieFXCore"],
            path: "Sources/RoadieBorders"
        ),
        .testTarget(
            name: "RoadieBordersTests",
            dependencies: ["RoadieBorders"],
            path: "Tests/RoadieBordersTests"
        ),
    ]
)
