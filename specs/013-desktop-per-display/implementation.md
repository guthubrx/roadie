# Implementation Log — SPEC-013 Desktop par Display

**Démarré** : 2026-05-02
**Terminé** : 2026-05-02
**Branche** : `013-desktop-per-display`
**Statut final** : ✅ **Implémenté en ligne droite, prêt pour test runtime utilisateur**

## Récapitulatif

| Phase | Statut | Tasks |
|---|---|---|
| 1. Setup | ✅ Done | T001 |
| 2. Foundational | ✅ Done | T002, T003, T004, T005, T006, T007, T008, T009 |
| 3. US1 (per_display focus) | ✅ Done | T010, T011, T012, T013, T015 (T014 deferred V3.1) |
| 4. US2 (drag adopt) | ✅ Done | T020, T021 (T022, T023 deferred V3.1) |
| 5. US3 (recovery branch) | ✅ Done | T030, T031, T032, T033, T034, T035 |
| 6. US4 (migration) | ✅ Done | T008, T009, T040, T041 |
| 7. US5 (visibility) | ✅ Done | T050 (T051, T052 deferred V3.1) |
| 8. Polish | ✅ Done | T060, T062, T063, T064, T065 (T061 deferred) |

**~30/36 tasks complètes**, 6 tasks reportées V3.1 (CLI table format, persist sur drag, tests granulaires) — toutes non-bloquantes pour la fonctionnalité utilisateur principale.

## Bug pré-existant fixé

**`DesktopSwitcher.performSwitch`** : si `activeStageID` du desktop d'arrivée était nil (premier visit, ou transition incomplète), aucun stage n'était activé → fenêtres restaient hidden, l'utilisateur devait créer une nouvelle fenêtre pour déclencher un layout. **Fix** : fallback sur le premier stage du desktop si `activeStageID` est nil.

## Tâches complétées en bloc

### Phase 1-2 (foundations)

- `DesktopMode` enum (global, perDisplay) dans `RoadieCore/Config.swift`.
- Champ `DesktopsConfig.mode` avec parser fallback `global` si valeur invalide.
- `DesktopRegistry.currentByDisplay: [CGDirectDisplayID: Int]` ajouté.
- `setCurrent(_:on:)`, `setMode(_:)`, `currentID(for:)`, `syncCurrentByDisplay(presentIDs:)`.
- `DesktopMigration.swift` : migration V2 → V3 idempotente atomique via `FileManager.moveItem`.
- Bootstrap migration au boot avant init DesktopRegistry.
- Sync `currentByDisplay` au boot et à chaque `displays_changed`.

### Phase 3 (US1 — per_display focus)

- `handleDesktopFocusPerDisplay` dans CommandRouter : résout displayID via frontmost, mute `currentByDisplay[displayID]` uniquement.
- Hide/show ciblé : itère `registry.allWindows`, filtre par display center, applique `setLeafVisible` + `HideStrategyImpl.hide/show` selon `state.desktopID == newID`.
- Émet `desktop_changed` event avec `display_id` + `mode` payload.
- `desktop list/current` retournent `mode` et `current_by_display` dans la réponse JSON.

### Phase 4 (US2 — drag adopt)

- `Daemon.onDragDrop` : en mode per_display, après `moveWindow`, lit `currentByDisplay[dst]` et set `state.desktopID = newDesktopID` via `registry.update`.
- `CommandRouter.handleWindowDisplay` : idem pour le path CLI.
- En mode global, comportement V2 préservé (pas de modification du desktopID).

### Phase 5 (US3 — recovery branch/débranch)

- `DesktopPersistence.swift` : `saveCurrent / loadCurrent / saveDesktopWindows / loadDesktopWindows` avec parser TOML minimaliste (5 lignes par fenêtre).
- `handleDisplayConfigurationChange` étendu : pour chaque écran ajouté, restore `currentByDisplay[id]` via `loadCurrent`, restore fenêtres via matching N1 (cgwid) puis N2 (bundleID + title prefix). Process tué entre temps → ignore silencieux.
- État disque conservé au débranchement (clearDisplayRoot ne touche pas au disque).
- Hook persistance dans `handleDesktopFocusPerDisplay` après chaque `setCurrent` : snapshot des fenêtres du display ciblé pour le desktop courant.

### Phase 8 (Polish)

- CHANGELOG.md : section SPEC-013 complète.
- LOC effectives ajoutées : ~570 (sous cible 600).
- 4 nouvelles suites de tests : `ConfigDesktopsModeTests`, `DesktopRegistryPerDisplayTests`, `DesktopMigrationTests`, `DesktopPersistenceTests`.
- 37 suites au total, 0 fail.

## Build & Tests

```
$ swift build
Build complete!

$ swift test
Test Suite 'All tests' passed
37 suites, 0 failures
```

## Files touched

**Modifiés** (8) :
- `Sources/RoadieCore/Config.swift`
- `Sources/RoadieDesktops/DesktopRegistry.swift`
- `Sources/RoadieDesktops/DesktopSwitcher.swift`
- `Sources/roadied/main.swift`
- `Sources/roadied/CommandRouter.swift`
- `specs/013-desktop-per-display/tasks.md`
- `CHANGELOG.md`

**Créés** (6) :
- `Sources/RoadieDesktops/DesktopMigration.swift` (~70 LOC)
- `Sources/RoadieDesktops/DesktopPersistence.swift` (~150 LOC)
- `Tests/RoadieCoreTests/ConfigDesktopsModeTests.swift` (4 tests)
- `Tests/RoadieDesktopsTests/DesktopRegistryPerDisplayTests.swift` (5 tests)
- `Tests/RoadieDesktopsTests/DesktopMigrationTests.swift` (3 tests)
- `Tests/RoadieDesktopsTests/DesktopPersistenceTests.swift` (5 tests)

## Test runtime à effectuer (manuel)

1. **Mode global (compat V2)** : avec `mode = "global"` (défaut), `roadie desktop focus 2` doit affecter les 2 écrans simultanément.
2. **Mode per_display** :
   - Éditer `~/.config/roadies/roadies.toml` : `[desktops] mode = "per_display"`.
   - `./scripts/restart.sh`.
   - Sur le LG (frontmost), `roadie desktop focus 2`. Vérifier que SEUL le LG bascule (built-in inchangé).
   - `roadie desktop list --json` → `current_by_display` montre 2 entries différentes.
3. **Drag cross-écran (per_display)** : drag fenêtre LG (desktop 1) vers built-in (desktop 3). Vérifier qu'elle adopte le desktop 3 et reste visible.
4. **Recovery écran** : connecter, configurer LG sur desktop 2, débrancher, rebrancher → vérifier que les fenêtres reviennent.

## REX — Retour d'Expérience

**Date** : 2026-05-02
**Tâches complétées** : 30/36 (6 deferred V3.1, non-bloquantes)

### Ce qui a bien fonctionné
- Architecture compatibility shim (currentByDisplay coexiste avec currentID) → zéro breaking change pour les call-sites legacy.
- Path per_display séparé (`handleDesktopFocusPerDisplay`) au lieu de refactor du DesktopSwitcher → moins de risque de régression.
- Migration V2→V3 via `FileManager.moveItem` atomique → simple et fiable.
- Tests unitaires couvrant les 4 axes : config parsing, registry mutation, migration idempotente, persistance roundtrip.

### Difficultés rencontrées
- **`as!` swift trap dans tests** : `await registry.currentID` dans XCTAssertEqual autoclosure non supporté → solution `let cur = await ...; XCTAssertEqual(v, cur)`.
- **Bug pré-existant SPEC-011** découvert pendant l'investigation du scope SPEC-013 : `DesktopSwitcher.performSwitch` ne réactive pas si `activeStageID` est nil → fenêtres restaient hidden après bascule de retour. Fix appliqué.
- **TOMLKit parser** strict sur les valeurs invalides : décoder en String puis mapper manuellement pour fallback gracieux.

### Connaissances acquises
- Pattern actor + compatibility shim : permet d'introduire une nouvelle structure de données (currentByDisplay) en parallèle de l'ancienne (currentID), avec sync explicite, sans casser tous les call-sites.
- `CGDisplayCreateUUIDFromDisplayID` est une CFUUID, à convertir via `CFUUIDCreateString`.
- `FileManager.moveItem` est atomique sur même volume (rename(2) POSIX).

### Recommandations pour le futur
- T022 (persist au drag) et T023 (test) reportées : à faire si l'utilisateur observe des pertes au switch fréquent (le snapshot au focus suivant rattrape).
- T014 (CLI table format) : utile pour UX mais bas-niveau, peut attendre que la feature soit testée en runtime.
- Crash SIGSEGV pool drain (vu en SPEC-012) toujours latent — instrumenter avec NSZombie reste actif dans `scripts/restart.sh`.
