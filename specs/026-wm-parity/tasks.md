# Tasks — SPEC-026 WM-Parity Hyprland/Yabai

**Feature**: WM-Parity (lot consolidé 9 features SIP-on)
**Branch**: `026-wm-parity`
**Plafond LOC** : 900 effectives.

Format strict : `- [ ] T<NNN> [P?] [USk?] Description + chemin`.

## Phase 1 — Setup (config TOML decoders)

- [ ] T001 Étendre `Sources/RoadieCore/Config.swift` : ajouter `focusFollowsMouse: Bool = false`, `mouseFollowsFocus: Bool = false` à `FocusConfig` + CodingKeys `focus_follows_mouse`, `mouse_follows_focus` + decoder defensif (fallback false sur valeur invalide)
- [ ] T002 Étendre `Sources/RoadieCore/Config.swift` : ajouter `smartGapsSolo: Bool = false` à `TilingConfig` + CodingKey `smart_gaps_solo` + decoder
- [ ] T003 Créer dans `Sources/RoadieCore/Config.swift` la struct `ScratchpadDef { name: String, cmd: String, match: ScratchpadMatch? }` + Codable + champ `scratchpads: [ScratchpadDef] = []` à la racine de `Config`
- [ ] T004 Créer dans `Sources/RoadieCore/Config.swift` les structs `SignalsConfig { enabled: Bool = true }` + `SignalDef { event: String, cmd: String }` + champ racine `signals: SignalsConfig` et liste `signalsList: [SignalDef] = []` (clé TOML `[[signals]]`)
- [ ] T005 Créer dans `Sources/RoadieCore/Config.swift` l'enum `StickyScope: String { case stage, desktop, all }` + ajouter champ `stickyScope: StickyScope?` à `RuleDef` existant + decoder fallback `.stage`
- [ ] T006 [P] Étendre `Tests/RoadieCoreTests/ConfigTests.swift` (créer le fichier si inexistant) : tests décodage toutes les nouvelles clés (defaults, valeurs valides, valeurs invalides → fallback)

## Phase 2 — Foundational (squelettes managers/watchers)

- [ ] T007 Créer `Sources/roadied/ScratchpadManager.swift` : classe `@MainActor ScratchpadManager` avec dict `[String: ScratchpadState]`, méthodes vides `toggle(name:)`, `attachWid(_:to:)`, `loadConfig(_:)` (juste signatures + stub log)
- [ ] T008 Créer `Sources/roadied/SignalDispatcher.swift` : classe `@MainActor SignalDispatcher` avec subscription `EventBus`, dict `[String: [SignalDef]]` (event → signals), méthodes vides `loadConfig(_:)`, `dispatch(event:payload:)`
- [ ] T009 Créer `Sources/roadied/FocusFollowsMouseWatcher.swift` : classe `@MainActor FocusFollowsMouseWatcher` avec `monitor: Any?`, `lastApply: Date`, `inhibitUntil: Date?`, méthodes vides `start()`, `stop()`, `setInhibit(durationSeconds:)`
- [ ] T010 Modifier `Sources/roadied/main.swift` : instancier `ScratchpadManager`, `SignalDispatcher`, `FocusFollowsMouseWatcher` au boot du Daemon, charger config initiale dans chacun

## Phase 3 — US1 Quick-wins commandes tree (Priority: P1)

**Goal**: 3 commandes `tiling balance|rotate|mirror` opérationnelles, déterministes, idempotentes.

**Independent Test**: cf. spec US1 — 3 fenêtres déséquilibrées + balance → équivalentes ; rotate 90 inverse orientations ; mirror x inverse positions left/right.

- [ ] T011 [US1] Ajouter méthode `balance(in scope:)` à `TilerProtocol` dans `Sources/RoadieTiler/TilerProtocol.swift` (signatures pures, sans implémentation)
- [ ] T012 [US1] Ajouter méthodes `rotate(angle:in scope:)` et `mirror(axis:in scope:)` à `TilerProtocol`
- [ ] T013 [P] [US1] Implémenter `BSPTiler.balance(in:)` dans `Sources/RoadieTiler/BSPTiler.swift` : itérer `allLeaves(in: scope)` + reset `adaptiveWeight = 1.0`
- [ ] T014 [P] [US1] Implémenter `BSPTiler.rotate(angle:in:)` dans `Sources/RoadieTiler/BSPTiler.swift` : fonction récursive sur containers ; 90 = swap orientation H↔V ; 180 = reverse children ; 270 = combinaison
- [ ] T015 [P] [US1] Implémenter `BSPTiler.mirror(axis:in:)` dans `Sources/RoadieTiler/BSPTiler.swift` : fonction récursive ; pour chaque container dont orientation == axis, reverse children
- [ ] T016 [P] [US1] Implémenter `MasterStackTiler.balance/rotate/mirror` dans `Sources/RoadieTiler/MasterStackTiler.swift` (semantics adaptées : balance = master_ratio = 0.5 ; rotate 90 = swap horizontal↔vertical layout ; mirror = swap master↔stack side)
- [ ] T017 [US1] Étendre `LayoutEngine` dans `Sources/RoadieTiler/LayoutEngine.swift` : ajouter méthodes publiques `balance()`, `rotate(angle:)`, `mirror(axis:)` qui délèguent au tiler courant + appellent `applyLayout()` post-mutation
- [ ] T018 [US1] Ajouter cases `"tiling.balance"`, `"tiling.rotate"`, `"tiling.mirror"` dans `Sources/roadied/CommandRouter.swift` ; parsing args ; appel `daemon.layoutEngine.balance/rotate/mirror`
- [ ] T019 [US1] Ajouter sous-verbes `tiling balance`, `tiling rotate <angle>`, `tiling mirror <axis>` dans `Sources/roadie/main.swift` (CLI client) : parsing argv + envoi commande JSON au daemon
- [ ] T020 [P] [US1] Créer `Tests/RoadieTilerTests/TreeOpsTests.swift` : tests unitaires balance (tree de 3 leaves déséquilibrés → poids 1.0 chacun), rotate 90 (H→V vérifié), rotate 180+180 idempotence, mirror x deux fois idempotence

## Phase 4 — US2 Smart gaps solo (Priority: P1)

**Goal**: si 1 fenêtre tilée sur un display, gaps = 0 sur ce display uniquement.

**Independent Test**: `smart_gaps_solo = true` + 1 fenêtre tilée → frame == visibleFrame du display ; ouvrir 2nde fenêtre → gaps reprennent.

- [ ] T021 [US2] Modifier `BSPTiler.applyAll` dans `Sources/RoadieTiler/BSPTiler.swift` : avant calcul des frames per-display, compter `displayLeaves.count` ; si `count == 1 && config.tiling.smartGapsSolo`, override `effectiveOuterGaps = 0` et `effectiveInnerGaps = 0` pour ce display
- [ ] T022 [US2] Idem dans `MasterStackTiler.applyAll` dans `Sources/RoadieTiler/MasterStackTiler.swift`
- [ ] T023 [P] [US2] Créer `Tests/RoadieTilerTests/SmartGapsTests.swift` : test pure de la fonction de detection count==1 + override logic ; mock display registry à 1 leaf vs 2 leaves

## Phase 5 — US3 Scratchpad toggle (Priority: P2)

**Goal**: `roadie scratchpad toggle <name>` lance/cache/restore une fenêtre déclarée.

**Independent Test**: cf. spec US3 — toggle round-trip term iTerm.

- [ ] T024 [US3] Implémenter `ScratchpadManager.loadConfig(_:)` dans `Sources/roadied/ScratchpadManager.swift` : indexe les `[[scratchpads]]` par nom, init `ScratchpadState` vides ; **chaque scratchpad attaché DOIT être marqué `stickyScope = .stage` par défaut sur son display** (FR-011)
- [ ] T025 [US3] Implémenter `ScratchpadManager.toggle(name:)` dans `Sources/roadied/ScratchpadManager.swift` : 3 branches (None → spawn cmd async, Visible → hide via HideStrategy.corner + save lastVisibleFrame, Hidden → restore frame + AX show)
- [ ] T026 [US3] Implémenter `ScratchpadManager.spawnAndAttach(scratchpad:)` dans `Sources/roadied/ScratchpadManager.swift` : `Process` async + watch EventBus.window_created sur 5s + heuristic match bundleID (parsing cmd) ou override `match.bundle_id` ; timeout → log warn + retour à None
- [ ] T027 [US3] Ajouter case `"scratchpad.toggle"` dans `Sources/roadied/CommandRouter.swift` : parse name, appel `daemon.scratchpadManager.toggle`
- [ ] T028 [US3] Ajouter sous-verbe `scratchpad toggle <name>` dans `Sources/roadie/main.swift`
- [ ] T029 [P] [US3] Créer `Tests/roadiedTests/ScratchpadTests.swift` : test toggle round-trip avec mock Process + EventBus simulator ; test timeout 5s ; test scratchpad name not configured → erreur

## Phase 6 — US4 Sticky cross-stage (Priority: P2)

**Goal**: rules `sticky_scope` honorées, fenêtre visible sur multiples stages.

**Independent Test**: cf. spec US4 — Slack sticky=stage visible sur tous stages d'un desktop.

- [ ] T030 [US4] Étendre `StageManager` dans `Sources/RoadieStagePlugin/StageManager.swift` : nouvelle méthode `applyStickyProjection(rules: [RuleDef])` qui, pour chaque rule avec `stickyScope != nil`, projette les wids matchées dans toutes les stages du scope (stage = toutes stages d'un (display, desktop) ; desktop = toutes stages d'un display ; all = display courant uniquement)
- [ ] T031 [US4] Modifier `StageManager.switchTo(stageID:)` dans `Sources/RoadieStagePlugin/StageManager.swift` : appel `applyStickyProjection` après le switch pour garantir que les wids sticky sont visibles sur la nouvelle stage
- [ ] T032 [US4] Modifier le hook `display_changed` dans `Sources/roadied/main.swift` ou daemon : pour les wids `sticky_scope = "all"`, déplacer vers le display courant via `setBounds` au visibleFrame du nouveau display
- [ ] T033 [P] [US4] Créer `Tests/RoadieStagePluginTests/StickyScopeTests.swift` : test scope=stage projette dans 2+ stages mêmes (display, desktop) ; test scope=desktop ; test scope=all + display switch ; **test invariant `widToScope` : une wid sticky ne DOIT figurer que dans une seule entrée widToScope canonique** (FR-017, pas de drift index)

## Phase 7 — US5 Follow focus bidirectionnel (Priority: P3)

**Goal**: focus_follows_mouse + mouse_follows_focus fonctionnels, opt-in TOML, anti-feedback loop.

**Independent Test**: cf. spec US5 — survol → focus, raccourci → warp curseur, simultané → pas de loop.

- [ ] T034 [US5] Implémenter `FocusFollowsMouseWatcher.start()` dans `Sources/roadied/FocusFollowsMouseWatcher.swift` : `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` ; throttle 100ms via lastApply Date ; check `inhibitUntil` ; check `MouseDragHandler.isDragging` ; identifier wid sous curseur via `topmostWindowID` ; si différente de focused → `FocusManager.setFocus(wid)`
- [ ] T035 [US5] Implémenter `FocusFollowsMouseWatcher.stop()` dans `Sources/roadied/FocusFollowsMouseWatcher.swift` : `NSEvent.removeMonitor(monitor)`
- [ ] T036 [US5] Étendre `FocusManager` dans `Sources/RoadieCore/FocusManager.swift` : ajouter méthode `setFocusFromShortcut(_ wid:)` distincte de `setFocus(_ wid:)` ; quand `mouseFollowsFocus == true`, après le SetFocused/Raise AX, calculer center de la nouvelle wid frame + `CGWarpMouseCursorPosition` + appel `focusFollowsMouseWatcher?.setInhibit(0.2)` pour bloquer le watcher pendant 200ms. **Ne PAS warper si l'origine du focus est un click souris** (FR-024) : `setFocusFromShortcut` n'est appelé QUE depuis les call sites raccourci/CLI, jamais depuis MouseRaiser ni depuis click handlers
- [ ] T037 [US5] Modifier les call sites HJKL/move/warp/stage_switch dans `Sources/roadied/CommandRouter.swift` : utiliser `setFocusFromShortcut` au lieu de `setFocus` quand applicable
- [ ] T038 [US5] Modifier `main.swift` ou daemon init : start/stop du `FocusFollowsMouseWatcher` selon `config.focus.focusFollowsMouse` ; reload-aware
- [ ] T039 [P] [US5] Créer `Tests/roadiedTests/FollowFocusTests.swift` : test setInhibit bloque effectivement le watcher pendant 200ms ; test feedback loop simulé (warp puis mouseMoved 100ms après) → 0 setFocus déclenché ; test isDragging skip

## Phase 8 — US6 Signal hooks (Priority: P3)

**Goal**: `[[signals]]` + EventBus subscription + Process async + timeout 5s + env injection.

**Independent Test**: cf. spec US6 — signal `window_focused` cmd `afplay ...` joue son à chaque focus.

- [ ] T040 [US6] Implémenter `SignalDispatcher.loadConfig(_:)` dans `Sources/roadied/SignalDispatcher.swift` : indexe les `[[signals]]` par event, store `enabled` flag
- [ ] T041 [US6] Implémenter `SignalDispatcher.subscribe()` dans `Sources/roadied/SignalDispatcher.swift` : `EventBus.shared.subscribe { event in self.dispatch(event) }` ; filter sur events supportés
- [ ] T042 [US6] Implémenter `SignalDispatcher.dispatch(event:)` dans `Sources/roadied/SignalDispatcher.swift` : si `!enabled` return ; pour chaque signal matching event, appel `executeCmd(signal.cmd, env: buildEnv(event))` async
- [ ] T043 [US6] Implémenter `SignalDispatcher.executeCmd(_:env:)` dans `Sources/roadied/SignalDispatcher.swift` : `Process` avec env injecté + `Task` async + timeout 5s via `DispatchQueue.global().asyncAfter` ; SIGTERM puis SIGKILL ; log info début + log warn si timeout
- [ ] T044 [US6] Implémenter `SignalDispatcher.buildEnv(event:)` : map des variables ROADIE_EVENT, ROADIE_WID, ROADIE_BUNDLE_ID, ROADIE_STAGE, ROADIE_DESKTOP, ROADIE_DISPLAY selon le payload de l'event
- [ ] T045 [US6] Modifier `main.swift` : appel `signalDispatcher.subscribe()` au boot ; reload-aware
- [ ] T046 [P] [US6] Créer `Tests/roadiedTests/SignalDispatcherTests.swift` : test env injection (mock Process + capture env) ; test timeout 5s déclenche kill ; test enabled=false → 0 spawn ; test event non supporté → ignore

## Phase 9 — Polish & Cross-Cutting Concerns

- [ ] T047 Ajouter logs structurés `signal_executed`, `scratchpad_toggled`, `tree_balanced`, `tree_rotated`, `tree_mirrored`, `smart_gaps_applied`, `sticky_projected`, `focus_follows_mouse_triggered`, `mouse_follows_focus_warped` dans les composants concernés (1 ligne info par opération)
- [ ] T048 Étendre `scripts/roadie-monitor.sh` : ajouter axes observabilité `signal_timeouts_5m`, `scratchpad_spawn_failures_5m`, `focus_loop_detected_5m`
- [ ] T049 Mesurer LOC effectif post-implémentation : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l` ; comparer au baseline pré-spec ; documenter delta dans implementation.md ; vérifier ≤ baseline + 900
- [ ] T050 Mettre à jour `~/.config/roadies/roadies.toml` example/template avec les nouvelles sections (commentées par défaut) en référence dans `quickstart.md`
- [ ] T051 Lancer `swift build -c release` final + `./scripts/install-dev.sh` + smoke test end-to-end (au moins 1 scénario par US)
- [ ] T052 Mettre à jour `implementation.md` : récap features livrées, LOC delta, tests passants, écarts vs spec si applicables

## Dépendances inter-stories

- **Phase 1 (Setup)** doit être 100% complète avant Phase 2.
- **Phase 2 (Foundational)** doit être 100% complète avant US1+.
- **US1** (P1) et **US2** (P1) sont indépendantes et peuvent être implémentées en parallèle.
- **US3** dépend de Phase 2 (ScratchpadManager skeleton).
- **US4** dépend de Phase 1 (StickyScope dans Config) et a impact sur StageManager — sérialiser après US1/US2 pour éviter conflits.
- **US5** dépend de Phase 2 (FocusFollowsMouseWatcher skeleton).
- **US6** dépend de Phase 2 (SignalDispatcher skeleton).
- **Phase 9 (Polish)** dépend de toutes les US complètes.

## Exécution parallèle (par US)

Au sein de **US1**, T013, T014, T015, T016 sont parallélisables (fichiers distincts ou méthodes indépendantes du même fichier — `[P]` marqué).
Au sein de **US3**, T024, T025, T026 sont séquentiels (même fichier ScratchpadManager.swift).
Au sein de **US6**, T040 à T044 sont séquentiels (même fichier SignalDispatcher.swift).

## Stratégie d'implémentation

**MVP** = Phase 1 + Phase 2 + US1 + US2.
- 23 tâches, ~250-300 LOC.
- Délivre les quick-wins immédiatement utiles (balance/rotate/mirror + smart_gaps).
- Aucune feature "passive risquée" activée.

**v1.0 complète** = MVP + US3 + US4.
- +20 tâches, ~250 LOC supplémentaires.
- Ajoute scratchpad et sticky.

**v1.1 power-user** = v1.0 + US5 + US6.
- +13 tâches, ~250 LOC supplémentaires.
- Ajoute follow focus et signals (les features les plus disruptives, opt-in obligatoire).

**Polish (Phase 9)** : appliqué une fois toutes les US livrées, garantit cohérence observabilité + LOC budget + smoke tests.

## Validation format checklist

Toutes les tâches respectent strictement :
- ✅ Préfixe `- [ ]`
- ✅ ID T001-T052 séquentiel
- ✅ `[P]` quand parallélisable
- ✅ `[USk]` pour Phase 3-8 uniquement (Setup/Foundational/Polish sans label)
- ✅ Description claire avec chemin de fichier
