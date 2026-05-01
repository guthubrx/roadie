# Implementation Plan: RoadieBlur (SPEC-009)

**Branch** : `009-blur` | **Date** : 2026-05-01

## Summary

Module FX simplissime : applique `CGSSetWindowBackgroundBlurRadius` via osax sur fenêtres tierces. Plafond LOC **150 strict**, cible 100. 2 fichiers Swift max.

## Technical Context

**Language** : Swift 5.9+
**Dependencies** : `RoadieFXCore.dylib` SPEC-004 uniquement
**Testing** : unit sur `RuleMatcher.radius(for: bundleID, defaultRadius:)`
**Target** : macOS 14+, SIP partial off
**Project Type** : `.dynamicLibrary`
**Performance** : SC-001 ≤ 150 ms, SC-002 LOC ≤ 150 strict
**Constraints** : 2 fichiers max, ≤ 100 LOC cumulés idéalement

## Constitution Check

✅ Tout passe. Module trivial.

## Project Structure

```text
Sources/
└── RoadieBlur/                      # NEW .dynamicLibrary
    └── Module.swift                 # ~80 LOC : config + rule matcher + module entry
                                     #          (un seul fichier suffit)

Tests/
└── RoadieBlurTests/
    └── RuleMatcherTests.swift       # ~30 LOC

specs/009-blur/
├── plan.md, spec.md, tasks.md, checklists/requirements.md
```

## Phase 1 — Design

```swift
// Module.swift
struct BlurConfig: Codable { var enabled: Bool; var defaultRadius: Int; var rules: [BlurRule] }
struct BlurRule: Codable { let bundleID: String; let radius: Int }

func radius(for bundleID: String, config: BlurConfig) -> Int {
    let rule = config.rules.first { $0.bundleID == bundleID }
    return clamp(rule?.radius ?? config.defaultRadius, 0, 100)
}

@MainActor final class BlurModule: FXModule {
    static let shared = BlurModule()
    private var trackedWindows: Set<CGWindowID> = []
    private var config = BlurConfig.default

    func subscribe(to bus) { bus.subscribe(...) }
    func handleEvent(_ event) {
        guard config.enabled else { return }
        // window_created → resolve bundleID → radius → bridge.send(.setBlur)
    }
    func shutdown() { trackedWindows.forEach { bridge.send(.setBlur(wid: $0, radius: 0)) } }
}
```

✅ Toutes gates passent post-design.
