# Tasks — Spec 162 (Scratchpad flottant, Dim Inactive & Scènes enrichies)

- [ ] T1 : Ajouter `tiling.scratchpad_enabled` et `fx.dim_inactive.{enabled,opacity}` dans `Config.swift`, `ConfigLoaderAndValidation.swift`, `SettingsCatalog`, `SettingsOrganization` et `SettingsCatalogTests`.
- [ ] T2 : Implémenter `ScratchpadService.swift`, l'exclusion de tuilage dans `DaemonSnapshot.swift`, la CLI `roadie scratchpad` et la commande lanceur.
- [ ] T3 : Implémenter `DimInactiveController.swift` et son démarrage dans `Sources/roadied/main.swift`.
- [ ] T4 : Enrichir `StageProjects.swift`, `TargetModeRuntimeController.swift` (`openProject` / `saveProject`) et `CLICommandRouter.swift` (`project info` et options `--url`/`--app`/`--note`).
- [ ] T5 : Écrire `Tests/RoadieDaemonTests/Spec162ScratchpadDimScenesTests.swift`, mettre à jour docs FR/EN, `CHANGELOG.md`, journal, exécuter les suites Swift/Python et obtenir la revue Bridget `Approuvé`.
