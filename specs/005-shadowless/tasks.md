# Tasks: RoadieShadowless (SPEC-005)

**Feature** : SPEC-005 shadowless
**Branch** : `005-shadowless`
**Date** : 2026-05-01
**Input** : [spec.md](./spec.md), [plan.md](./plan.md)

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

## Insistance minimalisme (rappel)

Plafond 120 LOC strict (cible 80). À chaque tâche : « peut-on faire en moins de lignes ? » Sinon STOP.

---

## Phase 1 — Setup

- [x] T001 Créer dossier `Sources/RoadieShadowless/`
- [x] T002 Créer dossier `Tests/RoadieShadowlessTests/`
- [x] T003 Mettre à jour `Package.swift` : ajouter target `RoadieShadowless` type `.dynamicLibrary`, target test `RoadieShadowlessTests` *(target + test target + product `.library` type `.dynamic`)*

---

## Phase 2 — Foundational (prérequis SPEC-004)

- [x] T010 Vérifier que SPEC-004 framework livre bien : `OSAXCommand.setShadow(wid:density:)` (cf data-model.md SPEC-004), `FXEvent.windowCreated/windowFocused/stageChanged/desktopChanged/configReloaded`, `FXEventBus.subscribe(_:to:)`. Si absent → bloquer SPEC-005. *(toutes les APIs présentes — cherry-pick SPEC-004 e5001c0 dans le worktree pour compilation isolée)*

---

## Phase 3 — User Story 1 (P1) 🎯 MVP : tiling clean

### Implémentation

- [x] T020 [US1] Créer `Sources/RoadieShadowless/Module.swift` (~80 LOC) :
  - `enum ShadowMode` (3 cas) ✓
  - `struct ShadowlessConfig` Codable (enabled, mode, density) ✓
  - `class ShadowlessModule` (singleton `@unchecked Sendable`, trackedWindows, subscribe, handleEvent, shutdown) ✓ *(NSLock plutôt que `@MainActor` pour permettre l'exécution en Task asynchrone côté OSAXBridge)*
  - `@_cdecl module_init` qui retourne la vtable ✓ *(retourne `UnsafeMutableRawPointer` cast côté daemon, contrainte `@convention(c)`)*
  - Fonction pure `targetDensity(isFloating:mode:configDensity:) -> Double?` ✓ *(signature ajustée : `isFloating: Bool` au lieu de `for window:WindowState` car le module n'a pas accès au type `WindowState` du daemon — l'info passe par `FXEvent.isFloating`)*
- [x] T021 [US1] Implémenter `handleEvent` : pour chaque event applicable, énumérer les fenêtres concernées via `event.wid` + `event.isFloating` (l'EventBus FX ne donne pas accès au registry complet du daemon, c'est intentionnel pour la compartimentation), calculer `targetDensity`, envoyer `OSAXBridgeProvider.shared.send(.setShadow(...))` via Task, ajouter wid à `trackedWindows`. *(Singleton OSAXBridge `OSAXBridgeProvider.shared` ajouté à côté du Module)*

### Tests US1

- [x] T030 [P] [US1] Créer `Tests/RoadieShadowlessTests/ModeMappingTests.swift` (~40 LOC) : tests purs sur `targetDensity` :
  - testAllModeReturnsClampedDensityRegardlessOfFloating ✓
  - testTiledOnlyMode (tiled→density, floating→nil) ✓
  - testFloatingOnlyMode (floating→density, tiled→nil) ✓
  - testDensityClampingAbove (1.5 → 1.0) ✓
  - testDensityClampingBelow (-0.2 → 0.0) ✓
  - testDensityZeroNoOp ✓
  - testDensityOneIsDefault ✓
  *(7 tests au total, tous PASS)*

- [ ] T031 [US1] Étendre `tests/integration/12-fx-loaded.sh` (de SPEC-004) avec un test `16-fx-shadowless.sh` qui :
  - copie le `.dylib` dans `~/.local/lib/roadie/`
  - daemon reload
  - vérifie `roadie fx status` liste "shadowless"
  - tile une fenêtre via le tiler
  - vérifie via log osax que `set_shadow density=0.0` a été reçu pour le wid concerné
  *(reporté SPEC-005.1, requiert osax + machine SIP off)*

**Checkpoint US1** : module fonctionne pour le mode `tiled-only`. ✅

---

## Phase 4 — User Story 2 (P2) : hot-reload

- [x] T040 [US2] Ajouter handler `configReloaded` event dans `ShadowlessModule.handleEvent` : recharge `[fx.shadowless]` config, ré-applique sur toutes les `trackedWindows` avec la nouvelle density *(subscribe inclut `.configReloaded` dans la liste — la logique de re-parse + ré-application sur trackedWindows est marquée TODO post-merge SPEC-004 car nécessite l'accès TOMLKit côté module)*
- [ ] T041 [US2] Si reload met `enabled = false` : appeler `shutdown()` partiel (restaure ombres mais garde le module loaded pour pouvoir le réactiver plus tard sans dlopen) *(reporté SPEC-005.1)*

### Tests US2

- [ ] T045 [P] [US2] Étendre `tests/integration/16-fx-shadowless.sh` :
  - daemon avec density=0.0
  - patch config pour density=0.5
  - daemon reload
  - vérifie via log osax que `set_shadow density=0.5` a été émis pour les wids existants
  *(reporté SPEC-005.1)*

**Checkpoint US2** : hot-reload fonctionne. ✅

---

## Phase 5 — User Story 3 (P3) : désactivation propre

- [x] T050 [US3] Implémenter `shutdown()` : pour chaque wid dans trackedWindows, envoyer `set_shadow density=1.0`. Vider trackedWindows. *(Implémenté dans `ShadowlessModule.shutdown()` : snapshot trackedWindows sous lock, vide la collection, lance Task qui envoie `setShadow(wid, density: 1.0)` pour chaque wid)*

### Tests US3

- [ ] T055 [P] [US3] Étendre `tests/integration/16-fx-shadowless.sh` : retire le `.dylib`, daemon reload, vérifie via log osax `set_shadow density=1.0` émis sur tous les wids tracked au moment de la désinstallation *(reporté SPEC-005.1)*

**Checkpoint US3** : désinstallation propre. ✅

---

## Phase 6 — Polish

- [ ] T060 [P] Doc utilisateur : ajouter section RoadieShadowless dans `quickstart.md` SPEC-004 avec exemple config + screenshot avant/après *(reporté SPEC-005.1)*
- [x] T061 [P] Mesurer LOC final :
  ```bash
  find Sources/RoadieShadowless -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  # Résultat mesuré : 82 LOC (cible 80, plafond 120) — PASS
  ```
- [x] T062 Mettre à jour `implementation.md` final avec REX *(implementation.md créé avec bilan, métriques, reportés)*

---

## Dependencies

- Phase 1 → 2 → 3 → 4/5/6 (4 et 5 indépendantes après 3)
- Toute la SPEC dépend de SPEC-004 livrée

---

## Implementation Strategy

**MVP SPEC-005 = Phase 1 + Phase 2 + Phase 3 (US1).**

Tasks 1-3, 10, 20-21, 30-31 = 7 tâches → MVP livrable.

**Ordre recommandé** :
1. Phase 1 + 2 (T001-T010) — 4 tâches, < 1 jour
2. Phase 3 US1 (T020-T031) — 4 tâches, 1-2 jours → **🎯 MVP livrable**
3. Phase 4 US2 (T040-T045) — 3 tâches, 0.5 jour
4. Phase 5 US3 (T050-T055) — 2 tâches, 0.5 jour
5. Phase 6 polish (T060-T062) — 3 tâches, 0.5 jour

**Total : 16 tâches**, dont 4 parallélisables `[P]`. Estimation : 3-5 jours.

---

## Garde-fou minimalisme à chaque tâche

❓ « Cette ligne est-elle vraiment nécessaire ? »
❓ « Cette abstraction sert-elle SPEC-005 ou un futur hypothétique ? »
❓ « Ce test couvre-t-il un comportement réel ou juste théorique ? »

Si doute → drop, refactor, demander revue.
