# Plan 166 — Fluidité 120 Hz & gestes trackpad, raccourcis autonomes et distribution 1-clic

## Architecture technique

### Lot 1 — Horloge adaptative 120 Hz, défilement fluide `scrolling` & gestes trackpad
1. **`Sources/RoadieCore/Config.swift` + `ConfigLoaderAndValidation.swift`** :
   - Ajouter `scrollingSmoothScroll: Bool = true`, `scrollingTrackpadGestures: Bool = true`, `scrollingTrackpadFingers: Int = 3` (clampé `3...4`) sur `TilingConfig` avec clés TOML `scrolling_smooth_scroll`, `scrolling_trackpad_gestures`, `scrolling_trackpad_fingers`.
   - Enregistrer les 3 clés dans `ConfigValidationRules.knownKeys["tiling"]`.
2. **`Sources/RoadieDaemon/SettingsCatalog.swift` + `Tests/RoadieDaemonTests/SettingsCatalogTests.swift`** :
   - Ajouter les 3 descripteurs FR/EN dans `.tuilage` et mettre à jour le compteur (`330 -> 333`).
3. **`Sources/RoadieDaemon/EffectAnimator.swift` + `FrameTransitionRuntime.swift`** :
   - Remplacer la cadence fixe `1.0 / 60` par `EffectAnimator.preferredFrameInterval(maxFPS:)` (détection `NSScreen.screens.map(\.maximumFramesPerSecond).max()`, bornée `30...120` Hz).
   - Autoriser `FrameTransitionRuntime.schedule` à accepter une `MotionPolicy` explicite optionnelle (`policyOverride`) afin que le mode `.scrolling` puisse glisser fluidement à ressort (`stiffness: 520, damping: 0.92`) lorsque `scrollingSmoothScroll = true`, même si `fx.animations.enabled = false`.
4. **`Sources/RoadieDaemon/DaemonSnapshot.swift` + `WindowCommands.swift`** :
   - Lors de `recenterScrollingRibbonIfNeeded(scope:snapshot:direction:)`, marquer `preservesSize = true` sur les commandes dont la taille courante est déjà à ±1 pt de la cible, et passer `transitionDirection` + `policyOverride` ressort si `scrollingSmoothScroll` est actif.
5. **`Sources/RoadieDaemon/ScrollingTrackpadGestureController.swift` + `Sources/roadied/main.swift`** :
   - Implémenter `ScrollingGestureDetector` (pur, déterministe, horloge injectable) gérant les gestes multi-doigts (3 ou 4 doigts, seuil horizontal `0.08`, ratio `1.6x`, cooldown `220 ms`) et `⌥ Option + scrollWheel` (accumulateur signé, seuil `24 pt`, cooldown `180 ms`).
   - Implémenter `ScrollingTrackpadGestureController` (`@MainActor`) utilisant des moniteurs passifs `NSEvent.addGlobalMonitorForEvents`, n'agissant que sur la stage active en mode `.scrolling`, et réagissant aux changements de config sans polling.
   - Brancher son cycle de vie dans `Sources/roadied/main.swift` (`start()` + `ShutdownRegistry.register`).

### Lot 2 — Raccourcis autonomes et préréglages natifs
1. **`Sources/RoadieCore/ShortcutPresets.swift`** :
   - Définir `ShortcutPresetID` (`standard`, `vim`, `minimal`), `ShortcutPreset`, `ShortcutMergeReport`, `ShortcutPresets.all`, `ShortcutPresets.merge(_:into:replaceExisting:)`, et `ShortcutPresets.renderDefaultConfigTOML(preset:)`.
2. **`Sources/RoadieDaemon/SettingsService` / `ShortcutConfigStore.swift` (ou helper dédié)** :
   - Permettre la lecture/écriture TOML propre des entrées `[[shortcuts]]` et l'initialisation atomique d'un `config.toml` neuf (`config init`), avec `ConfigReloadService.shared.reload` + notification `.roadieConfigDidReload` pour mise à jour immédiate de `RoadieCommandHotkeys`.
3. **`Sources/RoadieDaemon/CLICommandRouter.swift`** :
   - Ajouter la commande `shortcuts` (`list`, `presets`, `apply-preset`, `add`, `remove`, `check`), le sous-verbe `config init`, l'aide et la complétion zsh.
4. **`Sources/RoadieDaemon/SettingsShortcutsViews.swift` + `LauncherSystemCommands.swift`** :
   - Ajouter la barre de préréglages en 1 clic dans **Paramètres > Raccourcis** et 3 commandes dans le **Lanceur**.

### Lot 3 — Distribution 1-clic (sans notarisation Apple)
1. **`scripts/generate-cask` + `Casks/roadie.rb`** :
   - Script Python 3 stdlib générant `Casks/roadie.rb` (avec `--version`, `--sha256`, `--repo`, `--output`, `--check`).
   - Générer et versionner `Casks/roadie.rb` à la racine du dépôt.
2. **`scripts/package-dmg`** :
   - Respecter `ROADIE_CODESIGN_IDENTITY` si fourni (sinon signature ad hoc `-`), puis appeler `scripts/generate-cask` pour produire `dist/roadie.rb` aligné sur le SHA-256 réel du DMG.
3. **`scripts/install-release.sh`** :
   - Script bash robuste (`set -euo pipefail`) : détection arch/macOS >= 14, téléchargement GitHub Release ou `--dmg`, contrôle `shasum -a 256`, montage/démontage propre `hdiutil`, installation `~/Applications/Roadie.app` + `~/.local/bin/roadie` + `roadied`, `xattr -dr com.apple.quarantine`, initialisation non-destructive `config.toml` via `roadie config init --preset ...`, création et lancement du LaunchAgent, mode `--dry-run`.
4. **`.github/workflows/release.yml` + `Makefile`** :
   - Workflow de publication automatique sur tags `v*` (build release macOS Apple Silicon, DMG, SHA-256, Cask, GitHub Release, sans notarisation).
   - Cibles `make cask` et `make release-artifacts`.

### Lot 4 — Tests, documentation & livraison
- `Tests/RoadieDaemonTests/Spec166FluidityShortcutsTests.swift`
- `scripts/tests/test_distribution.py`
- Documentation FR/EN additive : `README.fr.md`, `README.md`, `docs/{fr,en}/{features,cli,use-cases}.md`, `CHANGELOG.md`, `.specify/memory/sessions/journal.md`.
- Exécution complète `./scripts/test --no-parallel`, `python3 -I -B -m unittest discover -s scripts/tests`, revue indépendante Bridget (`bridget_auto_delegate`), fusion sur `main`, `make install` (`roadied-cert`), `make restart`, `roadie daemon health --json`, nettoyage complet.
