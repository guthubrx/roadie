# Spec 159 — Maintenabilité, découpage modulaire et hygiène Swift 6

## Contexte

Plusieurs fichiers cœur de `RoadieCore` et `RoadieDaemon` ont dépassé 2 300 à 4 400 lignes (`LayoutMaintainer.swift`, `TargetOverlayPresenter.swift`, `Config.swift`, `StageCommands.swift`), certaines branches de focus/rappel de fenêtres absentes sont dupliquées dans `StageCommands.switchDisplay`, plusieurs classes de synchronisation simples utilisent encore `@unchecked Sendable` + `NSLock`, et 9 avertissements du compilateur subsistent dans `Sources/` et `Tests/`.

## Exigences fonctionnelles et techniques

- **FR-001 (Extraction de `StageFocusRecallService`)** : Centraliser `MissingWindowRecall`, le tri des candidats (`missingFocusCandidates`), le rappel des fenêtres absentes (`recallMissingWindows`) et les flux focus-ou-rappel ciblés (`focusOrRecallPreferred`, `focusOrRecallTarget`) dans `Sources/RoadieDaemon/StageFocusRecallService.swift`, et unifier les 3 branches de `StageCommands.switchDisplay` sans aucun changement de comportement.
- **FR-002 (Découpage modulaire des plus gros fichiers)** : Découper sans rupture d'API ni perte d'information (zéro élision) :
  - `Sources/RoadieCore/Config.swift` (2 389 lignes) en `Config.swift`, `ConfigTargetMode.swift` et `ConfigLoaderAndValidation.swift` ;
  - `Sources/RoadieDaemon/TargetOverlayPresenter.swift` (3 920 lignes) en `TargetOverlayPresenter.swift`, `TargetSearchSession.swift` et `TargetOverlayInputAndViews.swift` ;
  - `Sources/RoadieDaemon/LayoutMaintainer.swift` (4 478 lignes) en `LayoutMaintainer.swift` et `LayoutMaintainer+Models.swift`.
- **FR-003 (Migration vers `Sendable` strict avec `OSAllocatedUnfairLock`)** : Remplacer `@unchecked Sendable` + `NSLock` par `OSAllocatedUnfairLock` et `Sendable` strict sur les primitives sans I/O bloquant sous verrou : `LayoutPreviewHold`, `InteractiveWritePermit`, `RailSettingsCache`, `PlacementGeneration` et `AXUnresponsiveApps`.
- **FR-004 (Zéro avertissement de compilation Roadie)** : Corriger tous les avertissements restants dans `Sources/` (`WindowSwitcherWindowAccess`, `WindowTitleDragAccess`, `LauncherTerminal`, `RoadieScreenCoordinate`, `SearchBarRenderer`) et `Tests/` (`ReactiveTilingAXTests`, `Spec029ResizeTests`, `Audit022LotGTests`, `Spec061OverviewTests`).

## Critères d'acceptation

- Zéro avertissement du compilateur Swift sur l'ensemble des cibles `Sources/` et `Tests/` de Roadie.
- Tests dédiés `Spec159MaintenabiliteTests.swift` couvrant `StageFocusRecallService` et la sûreté concurrente des 5 types migrés vers `OSAllocatedUnfairLock`.
- 0 régression sur les suites complètes Swift (`./scripts/test --no-parallel`) et Python (`unittest`).
