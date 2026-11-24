# Plan — Spec 161 (Quick Wins Switcher & Lanceur)

## Architecture

1. **Configuration & Catalogue (`RoadieCore` + `SettingsCatalog`)**
   - `Sources/RoadieCore/WindowSwitcherConfig.swift` : ajout de `actionKeysEnabled: Bool = true` (`action_keys_enabled`).
   - `Sources/RoadieCore/ConfigTargetMode.swift` : ajout de `calcConversions: Bool = true` (`calc_conversions`), `emojiPicker: Bool = true` (`emoji_picker`), `timerEnabled: Bool = true` (`timer_enabled`).
   - `Sources/RoadieCore/ConfigLoaderAndValidation.swift` : enregistrement des 4 clés dans `knownKeys`.
   - `Sources/RoadieDaemon/SettingsCatalog.swift` : ajout des 4 descripteurs FR/EN (+ mise à jour de `SettingsCatalogTests.swift` : `316 -> 320`, `234 -> 238`).

2. **Switcher (`WindowSwitcherService`, `WindowSwitcherModel`, `WindowSwitcherPanel`, `WindowSwitcherController`)**
   - Ajout de `WindowSwitcherAction.summon` : rapatrie une fenêtre gérée vers la stage active de l'écran actif (retrait des autres stages/arbres, affectation à la stage active, mise à jour de l'arbre BSP, placement et focus).
   - `WindowSwitcherModel` : `scopeOverride: String?`, `effectiveScope`, `toggleScopeOverride(_:)`.
   - `WindowSwitcherPanel` : interception des touches directes (`w/q/m/h/s/a/d`) uniquement quand `!isSearchEditing` et `actionKeysEnabled`, avec modificateurs compatibles avec `navigationModifiers` (ou aucun modificateur), et indication du filtre de portée actif dans `selectionLabel`.
   - `WindowSwitcherController` : branchement de `onToggleScope` et mise à jour de `.summon` dans `perform(_:)`.

3. **Lanceur & CLI (`LauncherConverter`, `LauncherColorFormat`, `LauncherEmojiCatalog`, `LauncherTimerService`)**
   - `Sources/RoadieDaemon/LauncherConverter.swift` : convertisseur pur unités / bases / fuseaux horaires intégré dans `TargetSearchSession` lorsque `calcConversions` est actif.
   - `Sources/RoadieDaemon/LauncherEmojiCatalog.swift` : catalogue hors ligne bilingue émojis & symboles macOS/typographiques (`:…` / `emoji …`).
   - `Sources/RoadieDaemon/LauncherTimerService.swift` : service de minuteurs / Pomodoro local thread-safe (`OSAllocatedUnfairLock` + `DispatchSourceTimer` + horloge/notificateur injectables), intégré dans `TargetSearchSession`, `LauncherSystemCommands` et `CLICommandRouter` (`roadie timer start|pomodoro|status|cancel`).
   - `Sources/RoadieDaemon/LauncherSystemCommands.swift` : commande `"color-picker"` (`NSColorSampler` + `LauncherColorFormat`) et `"roadie-pomodoro"`.
   - `Sources/RoadieDaemon/LauncherList.swift` + `TargetSearchSession.swift` + `TargetOverlayPresenter.swift` : lignes `.utility` / `.calc` propres (copie presse-papiers ou lancement minuteur sur Retour).

4. **Tests & Documentation**
   - `Tests/RoadieDaemonTests/Spec161QuickWinsSwitcherLauncherTests.swift` : tests unitaires complets pour toutes les fonctionnalités, les 4 réglages TOML et leur désactivation.
   - `docs/fr/features.md`, `docs/en/features.md`, `CHANGELOG.md`, `.specify/memory/sessions/journal.md`.
