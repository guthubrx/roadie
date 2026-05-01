# Implementation Plan: RoadieOpacity (SPEC-006)

**Branch** : `006-opacity` | **Date** : 2026-05-01 | **Spec** : [spec.md](./spec.md)

## Summary

Module FX qui gère l'alpha (opacité) des fenêtres tierces via l'osax SPEC-004. 3 features dans un seul module : focus dimming (style Hyprland `dimstrength`), per-app baseline, stage hide via α=0 (alternative à HideStrategy.corner V2). Plafond LOC strict 220, cible 150.

## Technical Context

**Language** : Swift 5.9+, `@MainActor`

**Primary Dependencies** :
- `RoadieFXCore.dylib` (OSAXBridge, EventBus, FXModule, optionnel AnimationLoop pour `animate_dim`)
- Aucune dépendance externe

**Storage** : aucun (état RAM)

**Testing** :
- Unit : tests purs sur `targetAlpha(for:focused:rules:dim:)` (logique de combinaison baseline + per-app rules)
- Integration : `tests/integration/17-fx-opacity.sh` valide focus dim end-to-end via log osax `set_alpha`

**Target Platform** : macOS 14+, SIP partial off requis pour effet réel

**Project Type** : Swift target `.dynamicLibrary`

**Performance Goals** :
- SC-001 : latence ≤ 100 ms (sans animation) / ≤ duration + 50 ms (avec)
- SC-005 : LOC ≤ 220 strict (cible 150)

**Constraints** :
- Plafond LOC 220 strict
- Aucune dépendance nouvelle
- Restauration garantie au shutdown
- Compat avec ou sans SPEC-007 RoadieAnimations chargé (animate_dim devient no-op si absent)

## Constitution Check

| Principe | Conformité |
|---|---|
| **A — Préservation** | ✅ ajout pur, V1/V2/V3 inchangés |
| **A' — Suckless** | ✅ ≤ 220 LOC en 2-3 fichiers |
| **B' — Dépendances** | ✅ aucune nouvelle |
| **C' — APIs privées encadrées** | ✅ via osax SPEC-004 |
| **G — Minimalisme LOC** | ✅ plafond strict déclaré |
| **I' — Pluggable** | ✅ `.dynamicLibrary` séparé, désactivable via flag |

✅ Toutes gates passent.

### Coordination avec SPEC-002

`StageHideOverride` est un protocol injecté dans `StageManager.swift` SPEC-002. Si pas encore présent (selon où SPEC-006 est livré dans le temps), il faut soit :
- L'ajouter dans cette SPEC (extension SPEC-002 de +10 LOC max), OU
- Demander que SPEC-004 framework l'ajoute en advance (cf SPEC-004 plan.md T020 / FXModule)

Décision : **ajouté dans cette SPEC** (T015 dans tasks.md ci-dessous). C'est minimaliste (10 LOC) et localisé.

## Project Structure

```text
specs/006-opacity/
├── plan.md
├── spec.md
├── tasks.md
└── checklists/requirements.md

Sources/
└── RoadieOpacity/                   # NEW target .dynamicLibrary
    ├── Module.swift                 # ~80 LOC : module entry, vtable, singleton
    ├── DimEngine.swift              # ~50 LOC : targetAlpha logique pure
    └── Config.swift                 # ~30 LOC : OpacityConfig + AppRule TOML

Tests/
└── RoadieOpacityTests/
    └── DimEngineTests.swift         # ~50 LOC : tests purs targetAlpha

Sources/RoadieStagePlugin/
└── StageManager.swift               # EXT +10 LOC : protocol StageHideOverride

tests/integration/
└── 17-fx-opacity.sh                 # NEW
```

## Phase 0 — Research

Pas de recherche nécessaire. Tout l'inconnu est résolu par SPEC-004.

## Phase 1 — Design

### `targetAlpha` logique pure

```swift
func targetAlpha(focused: Bool,
                 baseline: Double,        // inactive_dim de config
                 perAppRule: Double?      // alpha de la rule si bundle_id match
                 ) -> Double {
    if focused {
        return perAppRule ?? 1.0
    } else {
        // Inactive : prendre le min entre baseline dim et per-app (si plus restrictif)
        if let rule = perAppRule {
            return min(rule, baseline)
        }
        return baseline
    }
}
```

→ Testable unitairement sans aucune dépendance UI.

### `StageHideOverride` protocol

```swift
// Dans Sources/RoadieStagePlugin/StageManager.swift (extension de +10 LOC)
public protocol StageHideOverride: AnyObject {
    func hide(stage: Stage, in registry: WindowRegistry)
    func show(stage: Stage, in registry: WindowRegistry)
}

extension StageManager {
    public var hideOverride: StageHideOverride? { ... }
    public func setHideOverride(_ override: StageHideOverride?) { ... }
}

// Dans hide() existant :
if let override = hideOverride {
    override.hide(stage: ..., in: ...)
} else {
    // fallback HideStrategy.corner V2
}
```

`OpacityModule` enregistre lui-même comme `StageHideOverride` au `subscribe()`, retire au `shutdown()`.

### Constitution Check (post Phase 1)

- ✅ Module ≤ 220 LOC (3 fichiers Swift, ~160 cumulés estimé)
- ✅ Aucune nouvelle dépendance
- ✅ Tests unitaires purs (targetAlpha)
- ✅ Extension SPEC-002 minimale (+10 LOC bornés)

## Complexity Tracking

Aucune violation. Module simple.
