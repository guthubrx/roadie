# Tasks: RoadieOpacity (SPEC-006)

**Feature** : SPEC-006 opacity | **Branch** : `006-opacity` | **Date** : 2026-05-01

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

## Garde-fou minimalisme

Plafond 220 LOC strict, cible 150. À chaque tâche : « peut-on faire en moins ? »

---

## Phase 1 — Setup

- [ ] T001 Créer `Sources/RoadieOpacity/` et `Tests/RoadieOpacityTests/`
- [ ] T002 Mettre à jour `Package.swift` : target `RoadieOpacity` `.dynamicLibrary` + target test

---

## Phase 2 — Foundational

- [ ] T010 Vérifier APIs SPEC-004 disponibles : `OSAXCommand.setAlpha`, `FXEvent.windowFocusChanged/.windowCreated/.stageChanged/.configReloaded`, `EventBus.subscribe`
- [ ] T015 Étendre `Sources/RoadieStagePlugin/StageManager.swift` (+10 LOC max) : protocol `StageHideOverride` + setter `setHideOverride()`. Hide call existant teste `if let override = hideOverride` avant fallback `HideStrategy.corner`. **Aucune régression V2** (fallback identique au comportement actuel).

---

## Phase 3 — User Story 1 (P1) MVP : focus dimming

- [ ] T020 [US1] Créer `Sources/RoadieOpacity/Config.swift` (~30 LOC) : `OpacityConfig` + `AppRule` Codable TOML
- [ ] T021 [US1] Créer `Sources/RoadieOpacity/DimEngine.swift` (~50 LOC) : fonction pure `targetAlpha(focused, baseline, perAppRule)` + helper `clampAlpha`
- [ ] T022 [US1] Créer `Sources/RoadieOpacity/Module.swift` (~80 LOC) :
  - `@_cdecl module_init` retourne vtable
  - `OpacityModule.shared` singleton `@MainActor`
  - `subscribe(to bus)` enregistre observers focus/created/stageChanged/configReloaded
  - `handleEvent` : énumère windows concernées, calcule target, envoie `setAlpha`
  - tracked windows set pour restauration shutdown

### Tests US1

- [ ] T030 [P] [US1] Créer `Tests/RoadieOpacityTests/DimEngineTests.swift` (~50 LOC) : 8 cas
  - focused sans rule → 1.0
  - focused avec rule 0.92 → 0.92
  - non-focused sans rule baseline 0.85 → 0.85
  - non-focused rule 0.92 baseline 0.85 → 0.85 (min gagne)
  - non-focused rule 0.5 baseline 0.85 → 0.5 (rule plus restrictive)
  - alpha clamp 1.5 → 1.0
  - alpha clamp -0.2 → 0.0
  - clamp 0.85 → 0.85 (no-op)
- [ ] T031 [US1] Créer `tests/integration/17-fx-opacity.sh` : 4 fenêtres tilées + module activé, switch focus, vérifie via log osax que les 3 wids non-focused reçoivent `set_alpha 0.85` et le focused `set_alpha 1.0`

**Checkpoint US1** : focus dimming opérationnel ✅

---

## Phase 4 — User Story 2 (P2) : per-app rules

- [ ] T040 [US2] Étendre `OpacityModule.handleEvent` : pour chaque fenêtre, lookup rule via `bundleID` match, applique `targetAlpha(rule:)`
- [ ] T045 [US2] Étendre `tests/integration/17-fx-opacity.sh` : ajouter règle iTerm2 α=0.92, vérifier que iTerm2 focused reçoit `set_alpha 0.92` (pas 1.0)

**Checkpoint US2** : per-app rules opérationnelles ✅

---

## Phase 5 — User Story 3 (P2) : stage hide via opacity

- [ ] T050 [US3] Étendre `OpacityModule` : si `config.stage_hide.enabled=true`, conform `StageHideOverride`, enregistre via `stageManager.setHideOverride(self)`
- [ ] T051 [US3] Implémenter `OpacityModule.hide(stage:)` : pour chaque wid du stage, envoie `setAlpha(wid, 0.0)`. `show(stage:)` : envoie `setAlpha(wid, 1.0)` (ou alpha selon focus rules)
- [ ] T055 [US3] Étendre `tests/integration/17-fx-opacity.sh` : créer 2 stages, basculer, vérifier que les wids du stage caché reçoivent `set_alpha 0.0` au lieu de `set_position` offscreen

**Checkpoint US3** : stage hide via α opérationnel ✅

---

## Phase 6 — Polish

- [ ] T060 Vérifier que `animate_dim = true` no-op si SPEC-007 RoadieAnimations pas chargé (graceful fallback). Si chargé : envoie une animation Animation au lieu d'un setAlpha direct.
- [ ] T061 [P] Mesurer LOC final ≤ 220 strict :
  ```bash
  find Sources/RoadieOpacity -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  ```
- [ ] T062 [P] Mettre à jour `quickstart.md` SPEC-004 avec exemple `[fx.opacity]`
- [ ] T063 Mettre à jour `implementation.md` final avec REX

---

## Dependencies

Phase 1 → 2 → 3 → 4/5/6 (4, 5 et 6 indépendants après 3)

## Implementation Strategy

**MVP = Phase 1+2+3 (US1)** = 7 tâches → focus dimming livré
Total : **18 tâches**, ~3-4 jours

## Garde-fou minimalisme

À chaque tâche : « cette ligne sert SPEC-006 réelle ou un futur hypothétique ? »
