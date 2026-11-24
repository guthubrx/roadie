# Plan 164 — Layouts avancés : Onglets (`tabbed`) & Ruban défilant (`scrolling`)

1. **Modèle & Config (`RoadieCore`)**
   - Étendre `WindowManagementMode` (`.tabbed`, `.scrolling`, alias, `allowsWindowOverlapOrOverflow`).
   - Ajouter `tabbedBarHeight` (`20...44`, défaut `28`) et `scrollingColumnWidth` (`0.25...1.0`, défaut `0.65`) dans `TilingConfig` (`Config.swift`) et `knownKeys["tiling"]` (`ConfigLoaderAndValidation.swift`).
   - Mettre à jour `SettingsCatalog.swift` (choix, libellés, alias, 2 nouveaux descripteurs) et `SettingsCatalogTests.swift` (`328 -> 330`, `246 -> 248`, plages `78 -> 80`).
2. **Stratégies de placement (`RoadieTiler`)**
   - Étendre `LayoutRequest` (`focusedWindowID`, `tabbedBarHeight`, `scrollingColumnWidth`) et `LayoutPlanner.plan`.
   - Créer `TabbedLayoutStrategy.swift` (empilement + `tabBarFrame` source unique de vérité) et `ScrollingLayoutStrategy.swift` (ruban horizontal centré sur le focus + clamp 24 pt sûr vis-à-vis de `HiddenWindowPlacement`).
3. **Daemon, Navigation, Barre d'onglets & UI (`RoadieDaemon` + `roadied`)**
   - `DaemonSnapshot.swift` & `LayoutMaintainer.swift` : transmettre `focusedWindowID`, `tabbedBarHeight`, `scrollingColumnWidth` dans `LayoutRequest`, et ne pas rejeter ni masquer les stages `allowsWindowOverlapOrOverflow` comme chevauchements invalides.
   - `WindowCommands.swift` : navigation `focus` (cyclage onglets en `tabbed`, défilement + réapplication ruban en `scrolling`) et `move left|right` (réordonnancement des membres dans `stageStore`).
   - `WidthAdjustmentService.swift` : autoriser `.scrolling`.
   - `StageTabBarController.swift` (NEW) : barre d'onglets flottante cliquable (zéro panneau quand aucune stage `.tabbed` ≥ 2 fenêtres), démarrée/arrêtée dans `startBorderComponent()` (`Sources/roadied/main.swift`).
   - `RailController.swift` : sous-menu « Mode de disposition » dans le menu contextuel de stage (`RailAction.setStageMode`).
   - `CLICommandRouter.swift` & `LauncherSystemCommands.swift` : aide CLI, validation mode et commandes lanceur `roadie-mode-tabbed` / `roadie-mode-scrolling`.
4. **Tests & Documentation**
   - `Tests/RoadieDaemonTests/Spec164TabbedScrollingTests.swift` : config/TOML/aliases/catalogue, géométrie `TabbedLayoutStrategy` (1 fenêtre vs N fenêtres + `tabBarFrame`), géométrie `ScrollingLayoutStrategy` (ruban tenant dans l'écran, défilement focus début/milieu/fin, compatibilité `HiddenWindowPlacement`), navigation `focus`/`move`, `StageTabBarController` (0 cible hors `.tabbed` ou 1 fenêtre, barre complète sur `.tabbed` ≥ 2 fenêtres), CLI `roadie mode tabbed|scrolling`.
   - Mettre à jour `docs/fr/features.md`, `docs/en/features.md`, `CHANGELOG.md`, `.specify/memory/sessions/journal.md`.
