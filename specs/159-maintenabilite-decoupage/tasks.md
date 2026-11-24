# Tâches — Spec 159 (Maintenabilité, découpage modulaire et hygiène Swift 6)

- [x] T001 — Cartographier les frontières exactes de découpage (`Config.swift`, `TargetOverlayPresenter.swift`, `LayoutMaintainer.swift`, `StageCommands.swift`) et inventorier tous les avertissements de compilation.
- [x] T002 — Extraire `StageFocusRecallService.swift` et dédupliquer les 3 branches de focus/rappel dans `StageCommands.swift`.
- [x] T003 — Découper `Config.swift` (`ConfigTargetMode.swift`, `ConfigLoaderAndValidation.swift`), `TargetOverlayPresenter.swift` (`TargetSearchSession.swift`, `TargetOverlayInputAndViews.swift`) et `LayoutMaintainer.swift` (`LayoutMaintainer+Models.swift`).
- [x] T004 — Migrer `LayoutPreviewHold`, `InteractiveWritePermit`, `RailSettingsCache`, `PlacementGeneration` et `AXUnresponsiveApps` vers `OSAllocatedUnfairLock` + `Sendable` strict.
- [x] T005 — Corriger tous les avertissements de compilation dans `Sources/` et `Tests/`.
- [x] T006 — Écrire `Spec159MaintenabiliteTests.swift`, exécuter les suites Swift et Python complètes, passer la revue Bridget, documenter la session 177 et livrer.
