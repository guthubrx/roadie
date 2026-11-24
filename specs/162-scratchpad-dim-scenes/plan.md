# Plan — Spec 162 (Scratchpad flottant, Dim Inactive & Scènes enrichies)

## Architecture

1. **Configuration & Catalogue (`RoadieCore` + `SettingsCatalog`)**
   - `Sources/RoadieCore/Config.swift` : `TilingConfig.scratchpadEnabled: Bool = true` (`scratchpad_enabled`), `DimInactiveConfig(enabled: Bool = false, opacity: Double = 0.22)` sur `EffectsConfig.dimInactive` (`dim_inactive`).
   - `Sources/RoadieCore/ConfigLoaderAndValidation.swift` : `"fx.dim_inactive"` dans `supportedTables` et `knownKeys`, `"scratchpad_enabled"` dans `knownKeys["tiling"]`.
   - `Sources/RoadieDaemon/SettingsCatalog.swift`, `SettingsCatalogAnimations.swift`, `SettingsOrganization.swift`, `SettingsCatalogTests.swift` (`320 -> 323`, `238 -> 241`).

2. **Scratchpad flottant (`Sources/RoadieDaemon/ScratchpadService.swift`)**
   - `PersistentScratchpadEntry`, `PersistentScratchpadBook`, `ScratchpadStore` (`JSONPersistence`, chemin via `TestEnvironment`).
   - `ScratchpadCommandService` : `assign`, `toggle`, `show`, `hide`, `release`, `list`, `centeredScratchpadFrame(saved:in:)`.
   - Intégration `DaemonSnapshot` (les fenêtres enregistrées en scratchpad sont protégées du retuilage automatique), `CLICommandRouter` (`scratchpad` dans `commandTable`, `isDaemonRouted`, `dispatch`), `LauncherSystemCommands` (`roadie-scratchpad-toggle`).

3. **Dim Inactive (`Sources/RoadieDaemon/DimInactiveController.swift`)**
   - `DimInactiveTarget`, `DimInactiveRendering` (protocole injectable pour les tests unitaires sans AppKit actif), `DimInactiveController` (abonné à `.roadieSnapshotDidPublish`, `.roadieWindowFramesDidRepublish`, `.roadieConfigDidReload`, `.roadieSettingsDidChange`, `NSWorkspace.didActivateApplicationNotification`).
   - Démarré proprement dans `Sources/roadied/main.swift` (`startBorderComponent()`).

4. **Scènes de travail enrichies (`Sources/RoadieDaemon/StageProjects.swift`, `TargetModeRuntimeController.swift`, `CLICommandRouter.swift`)**
   - Ajout rétrocompatible (`decodeIfPresent`) de `extraURLs`, `launchApps`, `displayCount`, `notes` dans `StageProject` + `StageProject.launchPlan(runningBundleIDs:)`.
   - `openProject(named:)` ouvre aussi `extraURLs` (URLs et dossiers locaux) et lance `launchApps` absentes ; `CLICommandRouter` ajoute `project info NAME [--json]` et les options `--url`/`--app`/`--note` sur `project save`.

5. **Tests & Documentation**
   - `Tests/RoadieDaemonTests/Spec162ScratchpadDimScenesTests.swift` + docs FR/EN + `CHANGELOG.md` + journal.
