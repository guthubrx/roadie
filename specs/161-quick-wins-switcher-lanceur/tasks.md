# Tasks — Spec 161 (Quick Wins Switcher & Lanceur)

- [ ] T1 : Ajouter les 4 réglages dans `WindowSwitcherConfig`, `TargetModeConfig`, `ConfigLoaderAndValidation`, `SettingsCatalog` et `SettingsCatalogTests`.
- [ ] T2 : Ajouter `WindowSwitcherAction.summon`, `scopeOverride` dans `WindowSwitcherModel`, les touches directes (`w/q/m/h/s/a/d`) dans `WindowSwitcherPanel` et leur câblage dans `WindowSwitcherController`.
- [ ] T3 : Créer `LauncherConverter.swift` (unités, bases, fuseaux horaires hors ligne).
- [ ] T4 : Créer `LauncherEmojiCatalog.swift` (émojis et typographie FR/EN) et `LauncherColorFormat` + commande `color-picker` dans `LauncherSystemCommands.swift`.
- [ ] T5 : Créer `LauncherTimerService.swift` (minuteur / Pomodoro) et câbler dans `CLICommandRouter` (`roadie timer`) et le lanceur (`TargetSearchSession`, `TargetOverlayPresenter`, `LauncherList`).
- [ ] T6 : Écrire `Tests/RoadieDaemonTests/Spec161QuickWinsSwitcherLauncherTests.swift` et mettre à jour `docs/fr/features.md`, `docs/en/features.md`, `CHANGELOG.md` et `.specify/memory/sessions/journal.md`.
- [ ] T7 : Exécuter `./scripts/test --no-parallel`, `python3 -I -B -m unittest discover -s scripts/tests`, revue indépendante Bridget jusqu'à `Approuvé`, livraison et nettoyage.
