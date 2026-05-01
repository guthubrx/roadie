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

- [ ] T001 Créer dossier `Sources/RoadieShadowless/`
- [ ] T002 Créer dossier `Tests/RoadieShadowlessTests/`
- [ ] T003 Mettre à jour `Package.swift` : ajouter target `RoadieShadowless` type `.dynamicLibrary`, target test `RoadieShadowlessTests`

---

## Phase 2 — Foundational (prérequis SPEC-004)

- [ ] T010 Vérifier que SPEC-004 framework livre bien : `OSAXCommand.setShadow(wid:density:)` (cf data-model.md SPEC-004), `FXEvent.windowCreated/windowFocused/stageChanged/desktopChanged/configReloaded`, `FXEventBus.subscribe(_:to:)`. Si absent → bloquer SPEC-005.

---

## Phase 3 — User Story 1 (P1) 🎯 MVP : tiling clean

### Implémentation

- [ ] T020 [US1] Créer `Sources/RoadieShadowless/Module.swift` (~80 LOC) :
  - `enum ShadowMode` (3 cas)
  - `struct ShadowlessConfig` Codable (enabled, mode, density)
  - `@MainActor class ShadowlessModule` (singleton, trackedWindows, subscribe, handleEvent, shutdown)
  - `@_cdecl module_init` qui retourne la vtable
  - Fonction pure `targetDensity(for:mode:configDensity:) -> Double?`
- [ ] T021 [US1] Implémenter `handleEvent` : pour chaque event applicable, énumérer les fenêtres concernées (via `EventBus.windowRegistry()` ou équivalent passé par SPEC-004), calculer `targetDensity`, envoyer `bridge.send(.setShadow(...))`, ajouter wid à `trackedWindows`

### Tests US1

- [ ] T030 [P] [US1] Créer `Tests/RoadieShadowlessTests/ModeMappingTests.swift` (~40 LOC) : tests purs sur `targetDensity` :
  - mode .all + density 0.0 + tiled → 0.0
  - mode .all + density 0.0 + floating → 0.0
  - mode .tiledOnly + tiled → density
  - mode .tiledOnly + floating → nil
  - mode .floatingOnly + tiled → nil
  - mode .floatingOnly + floating → density
  - density 1.5 → clamp 1.0
  - density -0.2 → clamp 0.0

- [ ] T031 [US1] Étendre `tests/integration/12-fx-loaded.sh` (de SPEC-004) avec un test `16-fx-shadowless.sh` qui :
  - copie le `.dylib` dans `~/.local/lib/roadie/`
  - daemon reload
  - vérifie `roadie fx status` liste "shadowless"
  - tile une fenêtre via le tiler
  - vérifie via log osax que `set_shadow density=0.0` a été reçu pour le wid concerné

**Checkpoint US1** : module fonctionne pour le mode `tiled-only`. ✅

---

## Phase 4 — User Story 2 (P2) : hot-reload

- [ ] T040 [US2] Ajouter handler `configReloaded` event dans `ShadowlessModule.handleEvent` : recharge `[fx.shadowless]` config, ré-applique sur toutes les `trackedWindows` avec la nouvelle density
- [ ] T041 [US2] Si reload met `enabled = false` : appeler `shutdown()` partiel (restaure ombres mais garde le module loaded pour pouvoir le réactiver plus tard sans dlopen)

### Tests US2

- [ ] T045 [P] [US2] Étendre `tests/integration/16-fx-shadowless.sh` :
  - daemon avec density=0.0
  - patch config pour density=0.5
  - daemon reload
  - vérifie via log osax que `set_shadow density=0.5` a été émis pour les wids existants

**Checkpoint US2** : hot-reload fonctionne. ✅

---

## Phase 5 — User Story 3 (P3) : désactivation propre

- [ ] T050 [US3] Implémenter `shutdown()` : pour chaque wid dans trackedWindows, envoyer `set_shadow density=1.0`. Vider trackedWindows. (Déjà esquissé en T020.)

### Tests US3

- [ ] T055 [P] [US3] Étendre `tests/integration/16-fx-shadowless.sh` : retire le `.dylib`, daemon reload, vérifie via log osax `set_shadow density=1.0` émis sur tous les wids tracked au moment de la désinstallation

**Checkpoint US3** : désinstallation propre. ✅

---

## Phase 6 — Polish

- [ ] T060 [P] Doc utilisateur : ajouter section RoadieShadowless dans `quickstart.md` SPEC-004 avec exemple config + screenshot avant/après
- [ ] T061 [P] Mesurer LOC final :
  ```bash
  find Sources/RoadieShadowless -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  # Doit afficher ≤ 120, idéalement ≤ 80
  ```
- [ ] T062 Mettre à jour `implementation.md` final avec REX

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
