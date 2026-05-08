# Journal d'Implémentation - Roadie Control & Safety

## Métadonnées

- **Spec** : 003-roadie-control-safety
- **Branche** : 003-roadie-control-safety
- **Démarré** : 2026-05-08
- **Terminé** : 2026-05-08

## Progression

### T001 - ADR frontiere API publique

- **Statut** : Complete
- **Fichiers modifies** :
  - `docs/decisions/002-control-safety-public-api-boundary.md`

### T002 - Target RoadieControlCenter

- **Statut** : Complete
- **Fichiers modifies** :
  - `Package.swift`
  - `Sources/RoadieControlCenter/ControlCenterPlaceholder.swift`
  - `Tests/RoadieControlCenterTests/ControlCenterPlaceholderTests.swift`

### T003 - Fixtures Spec003

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/Fixtures/Spec003/control-safety-valid.toml`
  - `Tests/RoadieDaemonTests/Fixtures/Spec003/control-safety-invalid.toml`

### T004 - Journal d'implementation

- **Statut** : Complete
- **Fichiers modifies** :
  - `specs/003-roadie-control-safety/implementation.md`

### T005 - Sections de config control/safety

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieCore/Config.swift`

### T006 - Catalogue d'evenements automation

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieCore/AutomationEvent.swift`
  - `Sources/RoadieCore/AutomationEventCatalog.swift`
  - `Tests/RoadieDaemonTests/EventCatalogTests.swift`

### T007 - Modeles core control/safety

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieCore/ControlSafetyModels.swift`
  - `Tests/RoadieDaemonTests/ControlSafetyModelTests.swift`

### T008 - Fixtures Spec003

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/Fixtures/Spec003/control-center-state.json`

### T009 - Tests baseline config

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/ConfigTests.swift`

### T010 - Validation fondations

- **Statut** : Complete
- **Commandes** :
  - `make build` : OK
  - `make test` : OK, 152 tests

### T011 - Tests service ControlCenterState

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/ControlCenterStateTests.swift`

### T012 - Tests rendu Control Center

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieControlCenterTests/ControlCenterStateRenderingTests.swift`

### T013 - Tests contrat CLI control status

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/ControlCommandTests.swift`

### T014 - ControlCenterStateService

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/ControlCenterStateService.swift`

### T015 - Commande control status

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/roadie/main.swift`
  - `Sources/RoadieDaemon/Formatters.swift`
  - `Sources/RoadieDaemon/DaemonSnapshot.swift`

### T016-T018 - Shell Control Center

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieControlCenter/ControlCenterApp.swift`
  - `Sources/RoadieControlCenter/ControlCenterMenu.swift`
  - `Sources/RoadieControlCenter/SettingsWindow.swift`

### T019 - Cycle de vie Control Center

- **Statut** : Complete
- **Fichiers modifies** :
  - `Package.swift`
  - `Sources/roadied/main.swift`

### T020 - Evenements Control Center

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieControlCenter/ControlCenterApp.swift`

### T021 - Documentation Control Center

- **Statut** : Complete
- **Fichiers modifies** :
  - `README.md`
  - `README.fr.md`
  - `docs/en/features.md`
  - `docs/fr/features.md`

### T022 - Validation US1

- **Statut** : Complete
- **Commandes** :
  - `make build` : OK
  - `make test` : OK, 155 tests

### T023 - Tests reload config

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/ConfigReloadTests.swift`

### T024 - Assertions evenements reload

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/AutomationEventTests.swift`

### T025 - Tests CLI config reload

- **Statut** : Complete
- **Fichiers modifies** :
  - `Tests/RoadieDaemonTests/ConfigCommandTests.swift`

### T026-T030 - Service reload atomique

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/ConfigReloadService.swift`
  - `Sources/RoadieDaemon/AutomationQueryService.swift`
  - `Sources/roadie/main.swift`
  - `Sources/RoadieDaemon/DaemonSnapshot.swift`

### T031-T032 - Documentation et validation US2

- **Statut** : Complete
- **Fichiers modifies** :
  - `docs/en/configuration-rules.md`
  - `docs/fr/configuration-rules.md`
- **Commandes** :
  - `make build` : OK
  - `make test` : OK

### T033-T044 - Restore safety

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/RestoreSafetyService.swift`
  - `Sources/RoadieDaemon/LayoutMaintainer.swift`
  - `Sources/roadied/main.swift`
  - `Sources/roadie/main.swift`
  - `Sources/RoadieDaemon/AutomationQueryService.swift`
  - `Tests/RoadieDaemonTests/RestoreSafetyTests.swift`
  - `Tests/RoadieDaemonTests/RestoreWatcherTests.swift`
  - `docs/en/features.md`
  - `docs/fr/features.md`
- **Notes** :
  - Snapshot de securite ecrit pendant les ticks de maintenance.
  - `restore-on-exit` raccorde au chemin de terminaison app et au chemin `--ticks`.
  - `roadied crash-watcher --pid PID` restaure seulement si le PID surveille a disparu.
  - La restauration utilise d'abord l'ID live si present, puis l'identite stable V2.

### T045-T053 - Fenetres systeme transitoires

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/TransientWindowDetector.swift`
  - `Sources/RoadieAX/SystemSnapshotProvider.swift`
  - `Sources/RoadieDaemon/LayoutMaintainer.swift`
  - `Sources/roadie/main.swift`
  - `Tests/RoadieDaemonTests/TransientWindowDetectorTests.swift`
- **Notes** :
  - Roles/subroles AX collectes sur les snapshots live.
  - Le maintainer suspend les mutations de layout non essentielles quand une sheet/dialog/popover/menu/open-save est active.
  - Recuperation conservative des transients hors ecran via frame visible du premier display.

### T054-T063 - Layout persistence V2

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/WindowIdentityService.swift`
  - `Sources/RoadieDaemon/StageStore.swift`
  - `Sources/RoadieDaemon/LayoutPersistenceV2Service.swift`
  - `Sources/RoadieDaemon/AutomationQueryService.swift`
  - `Sources/roadie/main.swift`
  - `Tests/RoadieDaemonTests/WindowIdentityTests.swift`
  - `Tests/RoadieDaemonTests/LayoutPersistenceV2Tests.swift`
  - `Tests/RoadieDaemonTests/StateRestoreCommandTests.swift`
- **Notes** :
  - L'identite V2 est persistee dans `PersistentStageMember`, qui est la couche durable de stage; `RoadieState` reste volontairement runtime et ID-only.
  - Le matching rejette les cas ambigus ou dupliques au lieu d'appliquer une restauration risquee.

### T064-T072 - Width presets et nudge

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/WidthAdjustmentService.swift`
  - `Sources/RoadieDaemon/LayoutIntentStore.swift`
  - `Sources/RoadieDaemon/LayoutCommandService.swift`
  - `Sources/roadie/main.swift`
  - `Tests/RoadieDaemonTests/WidthAdjustmentTests.swift`
  - `Tests/RoadieDaemonTests/PowerUserLayoutCommandTests.swift`
  - `docs/en/cli.md`
  - `docs/fr/cli.md`
- **Commandes exposees** :
  - `roadie layout width next`
  - `roadie layout width prev`
  - `roadie layout width nudge 0.05`
  - `roadie layout width ratio 0.67 --all`

### T073-T080 - Finition

- **Statut** : Complete
- **Fichiers modifies** :
  - `README.md`
  - `README.fr.md`
  - `docs/en/use-cases.md`
  - `docs/fr/use-cases.md`
  - `docs/en/events-query.md`
  - `docs/fr/events-query.md`
  - `specs/003-roadie-control-safety/quickstart.md`
  - `.specify/memory/sessions/index.md`
- **Scan de garde** :
  - `rg -n "import +(SkyLight|MultitouchSupport)|_SLS|SLS[A-Z]|CGS[A-Z]|dlopen" Sources Package.swift` : OK, aucun resultat.
  - `rg -n "NSAnimationContext|CAAnimation|animationDuration|animation_ms" Sources/RoadieControlCenter Sources/RoadieAX Sources/RoadieCore/ControlSafetyModels.swift Sources/RoadieDaemon/ConfigReloadService.swift Sources/RoadieDaemon/RestoreSafetyService.swift Sources/RoadieDaemon/TransientWindowDetector.swift Sources/RoadieDaemon/LayoutPersistenceV2Service.swift Sources/RoadieDaemon/WidthAdjustmentService.swift Sources/RoadieDaemon/WindowIdentityService.swift Sources/roadie Sources/roadied` : OK, aucun resultat.
  - Occurrences d'animation restantes dans le repo : rail existant et docs/specs hors scope de cette session.
- **Validation finale** :
  - `make build` : OK
  - `make test` : OK, 171 tests
  - Quickstart non destructif : `roadie control status --json`, `roadie config validate`, `roadie transient status --json`, `roadie state restore-v2 --dry-run --json`, `roadie restore snapshot --json`, `roadie restore status --json` : OK
  - Commandes mutantes quickstart non lancees sur le desktop reel (`restore apply`, `layout width ...`) ; couvertes par tests automatises.

## Résultat final

- **Termine** : 2026-05-08
- **Statut** : Complete
