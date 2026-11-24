# Plan d’implémentation — Spec 159 (Maintenabilité et découpage modulaire)

## Changements par module

1. **`RoadieDaemon` — Extraction `StageFocusRecallService`** :
   - Créer `Sources/RoadieDaemon/StageFocusRecallService.swift` regroupant `MissingWindowRecall`, `missingFocusCandidates`, `recallMissingWindows`, `focusOrRecallPreferred` et `focusOrRecallTarget`.
   - Brancher `StageCommands.swift` (`switchDisplay` et `StageCommandService.missingFocusCandidates`) dessus.

2. **`RoadieCore` — Découpage de `Config.swift`** :
   - Extraire les configurations Lanceur/Target/Grid/Titlebar dans `Sources/RoadieCore/ConfigTargetMode.swift`.
   - Extraire `RoadieConfigLoader`, la validation et les extensions de décodage dans `Sources/RoadieCore/ConfigLoaderAndValidation.swift`.
   - Promouvoir uniquement `decodeBarKeys`, `WindowManagementMode.init?(tomlValue:)` et `AnyKey` à `internal` pour le découpage intra-module.

3. **`RoadieDaemon` — Découpage de `TargetOverlayPresenter.swift` et `LayoutMaintainer.swift`** :
   - Extraire `TargetSearchDismissal` + `TargetSearchSession` dans `Sources/RoadieDaemon/TargetSearchSession.swift`.
   - Extraire `CommandBoxFollowUp`, `CommandBoxKeyEffect`, `SlashCommandModel` extension, `SearchKeyInput`, `KeyInput`, `TargetOverlayBadge`, `TargetOverlayWindow` et `TargetOverlayView` dans `Sources/RoadieDaemon/TargetOverlayInputAndViews.swift`.
   - Extraire les modèles d'arbitrage/refus (`ReconciledDisplayMove`, `RulePlacementDestination`, `ClampedFrame`, `FailedRestoration`, `FailedFrame`, `RevertedAppliedFrame`) dans `Sources/RoadieDaemon/LayoutMaintainer+Models.swift`.

4. **`Sendable` strict (`OSAllocatedUnfairLock`)** :
   - Migrer `LayoutPreviewHold`, `InteractiveWritePermit`, `RailSettingsCache`, `PlacementGeneration` et `AXUnresponsiveApps` (en gardant `NSLock` sur `WindowDragActivity` qui exécute du `flock` bloquant sous verrou).

5. **Hygiène compilation 0 avertissement** :
   - Corriger les 5 avertissements dans `Sources/` et les 4 avertissements dans `Tests/`.

## Vérification

- Ajout de `Tests/RoadieDaemonTests/Spec159MaintenabiliteTests.swift`.
- Exécution de `./scripts/test --no-parallel && python3 -I -B -m unittest discover -s scripts/tests` + vérification `0 warning:` dans les sources Roadie.
- Revue indépendante Bridget jusqu'à `Approuvé`, puis livraison, installation signée et vérification santé 5/5.
