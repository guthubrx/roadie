# Implementation Plan: RoadieCrossDesktop (SPEC-010)

**Branch** : `010-cross-desktop` | **Date** : 2026-05-01

## Summary

Module FX qui débloque le FR-024 SPEC-003 (DEFER V3). Permet `roadie window space N`, pinning auto par rule, sticky window, always-on-top, force-tiling fenêtres "non-resizable". Plafond LOC strict **450**, cible **300**.

## Technical Context

**Language** : Swift 5.9+, `@MainActor`
**Dependencies** : `RoadieFXCore.dylib` SPEC-004, accès aux desktop UUIDs SPEC-003 via EventBus.context
**Testing** : unit `PinEngine.match`, `LevelTracker.set/restore`. Integration : trigger window_created Slack stub, vérifier move_window_to_space émis.
**Target** : macOS 14+, SIP partial off requis
**Project Type** : `.dynamicLibrary`
**Performance** : SC-001 ≤ 300 ms, SC-004 LOC ≤ 450 strict
**Constraints** :
- 4 fichiers Swift max (Module + PinEngine + CommandHandler + Config)
- Force-tiling P3 optionnel, peut être livré séparément
- Extension SPEC-002 Tiler localisée (+20 LOC max) pour force-tiling, gated par flag

## Constitution Check

✅ Toutes gates passent. Module conforme.

### Coordination SPEC-003

`CrossDesktopModule` lit les desktop UUIDs et labels via une API publique exposée par SPEC-003 : `MultiDesktopManager.uuidFor(label:) -> String?` ou via `roadie desktop list --json` pipe (moins propre, mais fallback si API pas exposée). Préférer l'API directe.

## Project Structure

```text
specs/010-cross-desktop/
├── plan.md, spec.md, tasks.md, checklists/requirements.md

Sources/
└── RoadieCrossDesktop/              # NEW .dynamicLibrary
    ├── Module.swift                 # ~80 LOC : entry, vtable, singleton
    ├── PinEngine.swift              # ~80 LOC : window_created → rule match → move
    ├── CommandHandler.swift         # ~80 LOC : handlers `window space/stick/pin`
    └── Config.swift                 # ~50 LOC : PinRule, ForceTilingConfig

Sources/RoadieTiler/
└── LayoutEngine.swift               # EXT +20 LOC : hook force-tiling via setFrame osax si rule match

Sources/roadie/
└── main.swift                       # EXT +5 LOC : sous-verbe `window space|stick|pin`

Sources/roadied/
└── CommandRouter.swift              # EXT +15 LOC : route `window.*` vers FXRegistry

Tests/
└── RoadieCrossDesktopTests/
    └── PinEngineTests.swift         # ~50 LOC : rule match logic

tests/integration/
└── 22-fx-crossdesktop.sh            # NEW
```

## Phase 0/1 — Design

### `PinEngine`

```swift
struct PinEngine {
    let rules: [PinRule]
    let resolver: (String) -> String?  // label → UUID

    func match(window: WindowState) -> String? {
        // Returns target desktop UUID if rule matches, nil otherwise
        let rule = rules.first { $0.bundleID == window.bundleID }
        guard let rule = rule else { return nil }
        if let label = rule.desktopLabel { return resolver(label) }
        if let idx = rule.desktopIndex { return resolveByIndex(idx) }
        return nil
    }
}
```

### `Module.subscribe`

Subscribe `window_created` uniquement (pas focus/move pour éviter UX lutte).

### CLI extension

`roadie window space <selector>` → daemon route vers `CrossDesktopModule.handleSpaceCommand` qui résout selector via SPEC-003 API + envoie osax.

### Force-tiling hook (P3)

Dans `LayoutEngine.applyLayout`, juste avant l'appel AX `set frame`, check si bundleID est dans `force_tiling.bundle_ids`. Si oui : skip AX, appelle `OSAXBridge.setFrame` à la place. +20 LOC max dans LayoutEngine, gated par le module CrossDesktop chargé (sinon comportement V2 standard).

✅ Toutes gates post-design.
