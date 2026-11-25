# Tasks 166 — Fluidité 120 Hz & gestes trackpad, raccourcis autonomes et distribution 1-clic

- [x] **T001** Créer le worktree `feat/166-fluidite-raccourcis-distribution` et rédiger `spec.md`, `plan.md`, `tasks.md`.
- [x] **T002** Ajouter les 3 réglages `[tiling]` (`scrolling_smooth_scroll`, `scrolling_trackpad_gestures`, `scrolling_trackpad_fingers`) dans `Config.swift`, `ConfigLoaderAndValidation.swift`, `SettingsCatalog.swift` et mettre à jour `SettingsCatalogTests.swift`.
- [x] **T003** Mettre à niveau `EffectAnimator` (cadence adaptative jusqu'à 120 Hz ProMotion, zéro CPU au repos) et `FrameTransitionRuntime` (politique ressort optionnelle dédiée au ruban `scrolling`).
- [x] **T004** Activer le glissement fluide `preservesSize` du ruban `scrolling` dans `DaemonSnapshot.swift` et `WindowCommands.swift`.
- [x] **T005** Implémenter `ScrollingTrackpadGestureController.swift` (`ScrollingGestureDetector` pur + contrôleur trackpad 3/4 doigts & `⌥ + molette`) et le brancher dans `Sources/roadied/main.swift`.
- [x] **T006** Implémenter `Sources/RoadieCore/ShortcutPresets.swift` (`standard`, `vim`, `minimal`, fusion non-destructive, génération TOML initiale).
- [x] **T007** Ajouter les commandes CLI `roadie shortcuts` et `roadie config init` dans `CLICommandRouter.swift` (avec rechargement live et complétion zsh).
- [x] **T008** Ajouter les préréglages 1-clic dans `SettingsShortcutsViews.swift` et les commandes de preset dans `LauncherSystemCommands.swift`.
- [x] **T009** Créer `scripts/generate-cask`, `Casks/roadie.rb`, `scripts/install-release.sh`, `.github/workflows/release.yml` et mettre à jour `scripts/package-dmg` et `Makefile`.
- [x] **T010** Écrire les suites de tests `Tests/RoadieDaemonTests/Spec166FluidityShortcutsTests.swift` et `scripts/tests/test_distribution.py`.
- [x] **T011** Mettre à jour la documentation FR/EN (`README*.md`, `docs/{fr,en}/{features,cli,use-cases}.md`, `CHANGELOG.md`, `journal.md`).
- [ ] **T012** Exécuter les suites complètes Swift & Python, lancer la revue indépendante Bridget, fusionner sur `main`, installer (`roadied-cert`), redémarrer, vérifier `roadie daemon health --json` et nettoyer.
