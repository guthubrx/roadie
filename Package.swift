// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "roadies",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "roadied", targets: ["roadied"]),
        .executable(name: "roadie", targets: ["roadie"]),
        // SPEC-024 — RoadieRail est désormais une library liée statiquement à
        // roadied (fusion mono-binaire). Plus de produit `roadie-rail` exécutable.
        .library(name: "RoadieRail", targets: ["RoadieRail"]),
        .library(name: "RoadieCore", targets: ["RoadieCore"]),
        .library(name: "RoadieTiler", targets: ["RoadieTiler"]),
        .library(name: "RoadieStagePlugin", targets: ["RoadieStagePlugin"]),
        // SPEC-011 RoadieDesktops — multi-desktop virtuel (pivot AeroSpace)
        .library(name: "RoadieDesktops", targets: ["RoadieDesktops"]),
        // SPEC-004 fx-framework — chargé runtime via dlopen, JAMAIS lié au daemon
        .library(name: "RoadieFXCore", type: .dynamic, targets: ["RoadieFXCore"]),
        // SPEC-005 RoadieShadowless module opt-in
        .library(name: "RoadieShadowless", type: .dynamic, targets: ["RoadieShadowless"]),
        // SPEC-006 RoadieOpacity module opt-in
        .library(name: "RoadieOpacity", type: .dynamic, targets: ["RoadieOpacity"]),
        // SPEC-007 RoadieAnimations module opt-in
        .library(name: "RoadieAnimations", type: .dynamic, targets: ["RoadieAnimations"]),
        // SPEC-008 RoadieBorders module opt-in
        .library(name: "RoadieBorders", type: .dynamic, targets: ["RoadieBorders"]),
        // SPEC-009 RoadieBlur module opt-in
        .library(name: "RoadieBlur", type: .dynamic, targets: ["RoadieBlur"]),
        // SPEC-010 RoadieCrossDesktop module opt-in
        .library(name: "RoadieCrossDesktop", type: .dynamic, targets: ["RoadieCrossDesktop"])
    ],
    dependencies: [
        // TOML parser — justifié dans plan.md Complexity Tracking
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "RoadieCore",
            dependencies: [
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: "Sources/RoadieCore",
            linkerSettings: [
                // Framework privé SkyLight : nécessaire pour _SLPSSetFrontProcessWithOptions
                // et SLPSPostEventRecordTo (utilisés par WindowActivator pour
                // l'activation inter-app fiable sur Sonoma+/Sequoia/Tahoe).
                // Standard de l'industrie macOS WM (yabai, AeroSpace, Hammerspoon).
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks"]),
                .linkedFramework("SkyLight")
            ]
        ),
        .target(
            name: "RoadieTiler",
            dependencies: ["RoadieCore"],
            path: "Sources/RoadieTiler"
        ),
        .target(
            name: "RoadieStagePlugin",
            dependencies: ["RoadieCore", "RoadieTiler", "RoadieDesktops"],
            path: "Sources/RoadieStagePlugin"
        ),
        // SPEC-011 RoadieDesktops — desktops virtuels (pattern AeroSpace)
        .target(
            name: "RoadieDesktops",
            dependencies: [
                "RoadieCore",
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: "Sources/RoadieDesktops"
        ),
        .testTarget(
            name: "RoadieDesktopsTests",
            dependencies: ["RoadieDesktops", "RoadieCore"],
            path: "Tests/RoadieDesktopsTests"
        ),
        .executableTarget(
            name: "roadied",
            // SPEC-024 — RoadieRail intégré au binaire daemon (fusion mono-process).
            dependencies: ["RoadieCore", "RoadieTiler", "RoadieStagePlugin", "RoadieDesktops", "RoadieFXCore", "RoadieRail"],
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
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: "Sources/RoadieFXCore"
        ),
        .testTarget(
            name: "RoadieFXCoreTests",
            dependencies: ["RoadieFXCore"],
            path: "Tests/RoadieFXCoreTests"
        ),
        // SPEC-005 RoadieShadowless target
        .target(
            name: "RoadieShadowless",
            dependencies: ["RoadieCore", "RoadieFXCore"],
            path: "Sources/RoadieShadowless"
        ),
        .testTarget(
            name: "RoadieShadowlessTests",
            dependencies: ["RoadieShadowless"],
            path: "Tests/RoadieShadowlessTests"
        ),
        // SPEC-006 RoadieOpacity target
        .target(
            name: "RoadieOpacity",
            dependencies: ["RoadieCore", "RoadieFXCore"],
            path: "Sources/RoadieOpacity"
        ),
        .testTarget(
            name: "RoadieOpacityTests",
            dependencies: ["RoadieOpacity"],
            path: "Tests/RoadieOpacityTests"
        ),
        // SPEC-007 RoadieAnimations target
        .target(
            name: "RoadieAnimations",
            dependencies: ["RoadieCore", "RoadieFXCore"],
            path: "Sources/RoadieAnimations"
        ),
        .testTarget(
            name: "RoadieAnimationsTests",
            dependencies: ["RoadieAnimations", "RoadieFXCore"],
            path: "Tests/RoadieAnimationsTests"
        ),
        // SPEC-008 RoadieBorders target
        .target(
            name: "RoadieBorders",
            dependencies: [
                "RoadieCore",
                "RoadieFXCore",
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: "Sources/RoadieBorders"
        ),
        .testTarget(
            name: "RoadieBordersTests",
            dependencies: ["RoadieBorders"],
            path: "Tests/RoadieBordersTests"
        ),
        // SPEC-009 RoadieBlur target
        .target(
            name: "RoadieBlur",
            dependencies: ["RoadieCore", "RoadieFXCore"],
            path: "Sources/RoadieBlur"
        ),
        .testTarget(
            name: "RoadieBlurTests",
            dependencies: ["RoadieBlur"],
            path: "Tests/RoadieBlurTests"
        ),
        // SPEC-010 RoadieCrossDesktop target
        .target(
            name: "RoadieCrossDesktop",
            dependencies: ["RoadieCore", "RoadieFXCore"],
            path: "Sources/RoadieCrossDesktop"
        ),
        .testTarget(
            name: "RoadieCrossDesktopTests",
            dependencies: ["RoadieCrossDesktop"],
            path: "Tests/RoadieCrossDesktopTests"
        ),
        // SPEC-014/024 — stage-rail. Library liée à roadied (V2). En V1 c'était
        // un executableTarget séparé ; SPEC-024 a fusionné le rail dans le daemon.
        .target(
            name: "RoadieRail",
            dependencies: [
                "RoadieCore",
                .product(name: "TOMLKit", package: "TOMLKit")
            ],
            path: "Sources/RoadieRail"
        ),
        .testTarget(
            name: "RoadieRailTests",
            dependencies: ["RoadieRail"],
            path: "Tests/RoadieRailTests"
        )
    ]
)
