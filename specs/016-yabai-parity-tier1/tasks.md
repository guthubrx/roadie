# Tasks — SPEC-016 Yabai-parity tier-1

**Status**: Draft
**Spec**: [spec.md](spec.md)
**Plan**: [plan.md](plan.md)
**Last updated**: 2026-05-02

## Format

`- [ ] T<nnn> [P?] [US<k>?] Description avec chemin de fichier`

- `[P]` = parallélisable (fichiers indépendants).
- `[US<k>]` = appartient à user story k.
- `[FOUNDATIONAL]` = pré-requis transverse pour plusieurs US.

## Path Conventions

Tous les chemins relatifs à la racine du repo `<repo-root>` (worktree `.worktrees/016-yabai-parity-tier1/` non créé car branche déjà active dans le main worktree, cf. plan.md note).

---

## Phase 1 — Setup (Foundational, P0)

- [ ] T001 [SETUP] Vérifier état branche `016-yabai-parity-tier1` à jour avec main, working tree propre. (Aucune création de target SwiftPM neuve : tout vit dans `RoadieCore`/`RoadieTiler`/`roadied`/`roadie` existants.)
- [ ] T002 [SETUP] [P] Créer les 2 sous-dossiers `Sources/RoadieCore/Rules/` et `Sources/RoadieCore/Signals/` (conventions cohérentes avec `Watchers/`, `ScreenCapture/` déjà en place).
- [ ] T003 [SETUP] [P] Créer fichiers vides skeleton `Sources/RoadieCore/Rules/{RuleDef,RuleParser,RuleEngine}.swift`, `Sources/RoadieCore/Signals/{SignalDef,SignalDispatcher,SignalEnvironment}.swift`, `Sources/RoadieCore/Watchers/MouseFollowFocusWatcher.swift`, `Sources/RoadieCore/MouseInputCoordinator.swift`, `Sources/RoadieCore/InsertHintRegistry.swift` — chaque fichier avec en-tête `// SPEC-016 — <responsabilité>` et imports minimaux.
- [ ] T004 [SETUP] Smoke test : `swift build` clean après création des fichiers vides (vérifie que SwiftPM les détecte automatiquement, sans modification de Package.swift).
- [ ] T005 [SETUP] Vérifier que `swift test` continue de passer (toutes les SPECs précédentes restent vertes).

**Critère de fin Phase 1** : `swift build` + `swift test` clean ✓, structure de fichiers prête.

---

## Phase 2 — Foundational : Config + EventBus extensions

- [ ] T010 [FOUNDATIONAL] Étendre `Sources/RoadieCore/Config.swift` :
  - Ajouter struct `RuleDef` (cf. data-model §1) avec `init(from:)` Codable manuel — eager regex compilation, validation, anti-pattern check.
  - Ajouter struct `SignalDef` (cf. data-model §2) avec `supportedEvents` set fermé.
  - Ajouter enum `ManageMode`, struct `GridSpec` avec `parse(_:)` throws.
  - Ajouter enum `FocusFollowMode`, étendre `MouseConfig` avec `focusFollowsMouse`, `mouseFollowsFocus`, `idleThresholdMs` (defaults `.off`, `false`, `200`, parsing tolérant).
  - Ajouter struct `InsertConfig`, struct `SignalsConfig` (section globale `[signals]`).
  - Ajouter `rules: [RuleDef]?`, `signals: [SignalDef]?`, `insert: InsertConfig?`, `signalsGlobal: SignalsConfig?` à `Config`.
- [ ] T011 [FOUNDATIONAL] Créer `Sources/RoadieCore/Rules/RuleParser.swift` (~100 LOC) — fonction `parse(_ tomlRoot:)` retournant `(rules: [RuleDef], errors: [RuleParseError])`. Tolérant : skip invalides + log warn.
- [ ] T012 [FOUNDATIONAL] Étendre `Sources/RoadieCore/EventBus.swift` :
  - Ajouter factories `applicationFrontSwitched(bundle:pid:name:)`, `mouseDropped(x:y:displayID:frame:)`, `windowTitleChanged(wid:oldTitle:newTitle:)`, `spaceChanged(from:to:label:)`, `applicationLaunched`, `applicationTerminated`, `applicationVisible`, `applicationHidden`, `displayAdded`, `displayRemoved`, `displayChanged`, `windowMoved`, `windowResized`.
  - Documenter chaque factory avec liste env vars exposées dans `cli-signals.md`.
- [ ] T013 [FOUNDATIONAL] [P] Tests `Tests/RoadieCoreTests/ConfigRulesSignalsTests.swift` :
  - Parsing TOML valide → struct attendue.
  - Parsing TOML invalide → fallback defaults + erreurs collectées.
  - Anti-pattern `app=".*"` rejeté.
  - 50 % rules cassées → autres rules valides chargées (SC-016-05).
- [ ] T014 [FOUNDATIONAL] [P] Tests `Tests/RoadieCoreTests/EventBusFactoriesTests.swift` — vérifier sérialisation JSON-lines des nouvelles factories d'events.
- [ ] T015 [FOUNDATIONAL] Étendre `Sources/RoadieCore/Logger.swift` (si nécessaire) — sub-categories `rules`, `signals`, `mouse_follow`, `insert_hint` pour faciliter le filtrage `log stream --predicate 'category == "rules"'`.

**Critère de fin Phase 2** : Config étendue compile + tests parsing passent ✓, EventBus expose toutes les factories nécessaires.

---

## Phase 3 — User Story 1a : `window swap` (P1, MVP)

- [ ] T020 [US1a] Étendre `Sources/RoadieTiler/LayoutEngine.swift` avec `swap(_ wid: WindowID, direction: Direction) -> Bool` (~80 LOC) :
  - Trouver le neighbor directionnel via la logique existante (réutilise `findNeighbor`).
  - Si neighbor trouvé : échanger les `WindowID` dans les `LeafNode` correspondants, **sans toucher** aux `SplitNode` parents (ratios préservés).
  - Si pas de neighbor : retourne `false` (caller log warn).
  - Inter-display : si neighbor sur autre tree (display différent), échanger les wid dans les 2 trees respectifs et déclencher `applyLayout()` sur les 2.
- [ ] T021 [US1a] Étendre `Sources/roadied/CommandRouter.swift` avec `case "window.swap"` :
  - Lit `args["direction"]`, valide.
  - Lit `daemon.registry.focusedWindowID`, error si nil.
  - Appelle `daemon.layoutEngine.swap(wid, direction:)`.
  - Si `false` → error `no_neighbor`.
  - Si OK → `daemon.applyLayout()`, retour `{swapped_with: <other_wid>, from_wid, from_display, to_display}`.
- [ ] T022 [US1a] Étendre `Sources/roadie/main.swift` avec verbe `window swap <dir>`.
- [ ] T023 [US1a] [P] Tests `Tests/RoadieTilerTests/LayoutEngineSwapTests.swift` :
  - `[A | B]`, swap left → `[B | A]`, focus B
  - `[A | (B / C)]`, swap right → A ↔ B, sous-arbre `(_ / C)` intact
  - Solo → false + warn
  - Floating → false + warn
  - Inter-display → frames adoptées
- [ ] T024 [US1a] Test acceptance bash `Tests/16-swap.sh` :
  - 3 fenêtres tilées Terminal, swap left/right, vérifier `roadie windows list` reflète l'échange.
  - Latence mesurée < 50 ms.
- [ ] T025 [US1a] Mettre à jour `implementation.md` avec REX US1a.

**Critère de fin US1a** : test acceptance PASS, swap fonctionnel inter-display.

---

## Phase 4 — User Stories 1b/1c : MouseFollowFocusWatcher + MouseInputCoordinator + mouse_follows_focus (P1, MVP)

- [ ] T030 [US1bc] Créer `Sources/RoadieCore/MouseInputCoordinator.swift` (~60 LOC) :
  - `@MainActor`, `dragActive: Bool` (let/var), `notifyDragStarted()`, `notifyDragEnded()`.
  - Pas de hook event direct — juste un pass-through de flag (cf. data-model §3).
- [ ] T031 [US1bc] Étendre `Sources/RoadieCore/MouseDragHandler.swift` (SPEC-015) :
  - Ajouter `weak var coordinator: MouseInputCoordinator?`.
  - Au début du drag (mouseDown matched modifier) : `coordinator?.notifyDragStarted()`.
  - Au mouseUp : `coordinator?.notifyDragEnded()`.
- [ ] T032 [US1bc] Créer `Sources/RoadieCore/Watchers/MouseFollowFocusWatcher.swift` (~120 LOC) :
  - `@MainActor`, owns un `Timer` 50 ms.
  - Tick : si `config.focusFollowsMouse == .off` ou `coordinator?.dragActive == true` → return early.
  - Sinon : poll `NSEvent.mouseLocation`, détecter idle `idleThresholdMs`, trouver fenêtre via `registry.windowAt(point:)`, `focusManager.setFocus(to:source: .mouseFollow)`.
  - Si `.autoraise` → `windowActivator.raise(wid)`.
- [ ] T033 [US1bc] Étendre `Sources/RoadieCore/WindowRegistry.swift` avec helper `windowAt(_ point: NSPoint) -> CGWindowID?` :
  - Itère `allWindows.reverse()` (z-order MRU front), retourne le premier dont `frame.contains(point)`.
  - Skip les fenêtres `subrole == kAXSystemDialog` ou non-tracked (Dock, MenuBar).
- [ ] T034 [US1bc] Étendre `Sources/RoadieCore/FocusManager.swift` :
  - Ajouter enum `FocusSource { case keyboard, mouseClick, mouseFollow, rule, external }`.
  - Ajouter `setFocus(to wid:, source:)` (préserver `setFocus(to:)` existant qui appelle avec `.external` par défaut).
  - À chaque `setFocus(.., source: .keyboard)` ET `MouseConfig.mouseFollowsFocus == true` → calculer centre du `frame` de wid, `CGWarpMouseCursorPosition` (avec conversion Y NS↔CG, cf. mouse-follows-config.md §3).
- [ ] T035 [US1bc] Mettre à jour TOUS les call sites de `setFocus(to:)` qui sont des commandes clavier pour passer `.keyboard` :
  - `CommandRouter` : `focus`, `window.swap`, `window.warp`, `window.display`, `window.desktop`, `desktop.focus`, `stage.switch`.
  - Vérifier que `MouseRaiser` passe `.mouseClick` et `MouseFollowFocusWatcher` passe `.mouseFollow`.
- [ ] T036 [US1bc] Étendre `Sources/roadied/main.swift` :
  - Instancier `MouseInputCoordinator` + `MouseFollowFocusWatcher`.
  - Câbler : `coordinator.dragHandler = mouseDragHandler` ; `coordinator.followWatcher = followWatcher` ; `mouseDragHandler.coordinator = coordinator` ; `followWatcher.coordinator = coordinator`.
  - Démarrer/arrêter le watcher selon `config.mouse.focusFollowsMouse != .off`.
- [ ] T037 [US1bc] [P] Tests `Tests/RoadieCoreTests/MouseFollowFocusWatcherTests.swift` :
  - `autofocus_after_idle_200ms` (mock NSEvent.mouseLocation, mock registry, vérifier setFocus appelé).
  - `no_focus_during_jitter` (curseur en mouvement continu pendant 1 s → setFocus pas appelé).
  - `suspended_during_drag` (mock `coordinator.dragActive = true`).
  - `ignore_dock_menubar_zones` (mock `windowAt` retournant nil).
- [ ] T038 [US1bc] [P] Tests `Tests/RoadieCoreTests/FocusManagerSourceTests.swift` :
  - `keyboard_source_warps_cursor_when_enabled`
  - `mouseClick_source_does_not_warp`
  - `mouseFollow_source_does_not_warp`
  - `disabled_config_does_not_warp_even_with_keyboard`
- [ ] T039 [US1bc] Test acceptance bash `Tests/16-focus-follows-mouse.sh` :
  - Active `focus_follows_mouse = "autofocus"` + reload.
  - Lance 2 Terminal côte à côte.
  - `cliclick m:300,400` (curseur sur Terminal 1) → vérifier `roadie daemon status | jq .focused` = wid 1.
  - `cliclick m:1300,400` (curseur sur Terminal 2) → attendre 250 ms → vérifier focused = wid 2.
- [ ] T040 [US1bc] Test acceptance bash `Tests/16-mouse-follows-focus.sh` :
  - Active `mouse_follows_focus = true`.
  - Position curseur via `cliclick p:0,0`.
  - `roadie focus right` → vérifier `cliclick p` retourne coords du centre de la fenêtre focused.

**Critère de fin US1bc** : tests acceptance PASS, coexistence avec MouseDragHandler (SPEC-015) validée.

---

## Phase 5 — User Story 2 : Système de règles déclaratif (P1)

- [ ] T050 [US2] Créer `Sources/RoadieCore/Rules/RuleEngine.swift` (~250 LOC) :
  - `@MainActor`, owns `rules: [RuleDef]`.
  - `applyForNewWindow(_ wid:)` : itère rules dans l'ordre, premier match → applique effets dans l'ordre (manage, float, sticky, space, display, grid).
  - `reload(_:)`, `applyAll()`, `handleTitleChange(wid:newTitle:)` (filtrer rules avec `reapplyOnTitleChange`).
  - Helpers : `matchesApp(_ rule, window)`, `matchesTitle(_ rule, window)`.
- [ ] T051 [US2] Créer `Sources/RoadieCore/Rules/RuleEffects.swift` (~80 LOC) — fonctions pure pour appliquer chaque effet :
  - `applyManage(_:to:registry:)`, `applyFloat`, `applySticky`, `applySpace(_:to:desktopRegistry:)`, `applyDisplay(_:to:displayManager:)`, `applyGrid(_:to:layoutEngine:)`.
- [ ] T052 [US2] Étendre `Sources/RoadieCore/WindowRegistry.swift` avec callback `onWindowAdded: ((CGWindowID) -> Void)?` invoqué synchronement après l'insertion mais avant le routing initial du DesktopRegistry.
- [ ] T053 [US2] Étendre `Sources/roadied/main.swift` :
  - Instancier `RuleEngine` avec les rules parsées.
  - Câbler `registry.onWindowAdded = { [weak ruleEngine] wid in ruleEngine?.applyForNewWindow(wid) }`.
  - Subscribe EventBus `window_title_changed` → `ruleEngine.handleTitleChange(...)`.
- [ ] T054 [US2] Étendre `Sources/roadied/CommandRouter.swift` :
  - `case "rules.list"` : retourne liste indexée + rejected_at_parse.
  - `case "rules.apply"` : `args["all"] = true` → `ruleEngine.applyAll()`, retour stats.
- [ ] T055 [US2] Étendre `Sources/roadie/main.swift` avec verbes `rules list` (avec `--json` opt) et `rules apply --all`.
- [ ] T056 [US2] [P] Tests `Tests/RoadieCoreTests/RuleEngineTests.swift` :
  - `first_match_wins` (2 rules matchent, seule la première applique)
  - `manage_off_marks_non_tileable`
  - `space_routes_to_desktop`
  - `display_moves_to_target_screen`
  - `grid_places_correctly`
  - `regex_app_matches_case_insensitive`
  - `regex_title_works`
  - `reject_match_all_pattern` (5 patterns dangereux)
  - `accept_match_all_with_title_filter` (`app=".*", title="^Settings$"` accepté)
  - `regex_invalid_skipped_with_log`
  - `reapply_on_title_change_true_re_evaluates`
  - `reapply_on_title_change_false_does_not`
  - `rule_space_overrides_desktop_default` (R-004 risque mitigé)
  - `apply_all_re_evaluates_existing_windows`
- [ ] T057 [US2] Test acceptance bash `Tests/16-rules-manage-off.sh` :
  - Crée TOML avec rule `app="Calculator", manage="off"`.
  - Reload daemon.
  - Lance Calculator → vérifier `roadie windows list | grep Calculator` show `is_tiled=false`.
- [ ] T058 [US2] Test acceptance bash `Tests/16-rules-space-display-grid.sh` :
  - 3 rules : Slack→space=5, WezTerm→display=2, Calculator→grid="4:4:3:3:1:1".
  - Reload, lance les 3 apps, vérifier placement attendu.
- [ ] T059 [US2] Mettre à jour `implementation.md` avec REX US2.

**Critère de fin US2** : tests acceptance PASS, anti-pattern detection en place, parser tolérant.

---

## Phase 6 — User Story 3 : Signals utilisateur shell (P1)

- [ ] T080 [US3] Créer `Sources/RoadieCore/Signals/SignalEnvironment.swift` (~100 LOC) — fonction `envVars(for event:, registry:)` qui construit le `[String: String]` selon la table data-model §2.
- [ ] T081 [US3] Créer `Sources/RoadieCore/Signals/SignalDispatcher.swift` (~250 LOC) :
  - `@MainActor`, owns `signals: [SignalDef]`, `queue: Deque<DesktopEvent>` (cap configurable).
  - `start()` : task async qui consomme `eventBus.subscribe()`. Skip si `payload["_inside_signal"] == "1"`.
  - Worker : pop FIFO, match contre signals, exec async pour chaque match.
  - Exec : `Foundation.Process` détaché, env vars construites via `SignalEnvironment.envVars(...)` + `ROADIE_INSIDE_SIGNAL=1` + `ROADIE_EVENT=<name>` + `ROADIE_TS=<iso>`.
  - Timeout `DispatchSourceTimer` (default 5 s) : SIGTERM puis +1 s SIGKILL.
  - Capture stdout/stderr cap 16 KB.
  - `terminationHandler` : log warn si exit != 0 OU timeout, increment metrics.
- [ ] T082 [US3] Implémenter ou import `Deque` (si Swift Collections pas dispo : implémenter en interne ~30 LOC dans `SignalDispatcher.swift` ou `Sources/RoadieCore/Internal/Deque.swift`).
- [ ] T083 [US3] Étendre `Sources/roadied/CommandRouter.swift` :
  - Propager `_inside_signal` flag du payload IPC vers les events publiés pendant le traitement de la commande (re-entrancy guard côté daemon, R-006).
  - `case "signals.list"` : retourne signals + metrics.
- [ ] T084 [US3] Étendre `Sources/roadie/main.swift` :
  - Verbe `signals list`.
  - Lecture env var `ROADIE_INSIDE_SIGNAL` au boot du CLI, propage dans le payload IPC `_inside_signal: "1"` si présent (R-006 propagation).
- [ ] T085 [US3] Étendre `Sources/roadied/main.swift` :
  - Instancier `SignalDispatcher` avec signals parsés + cap/timeout depuis `SignalsConfig`.
  - `dispatcher.start()` au boot, `dispatcher.stop()` au SIGTERM.
- [ ] T086 [US3] [P] Tests `Tests/RoadieCoreTests/SignalDispatcherTests.swift` :
  - `exec_simple_action_succeeds` (action `echo`, vérifier exit code 0)
  - `exec_with_env_vars_propagates` (action `test "$ROADIE_WINDOW_BUNDLE" = "test.bundle"`)
  - `timeout_kills_with_sigterm_then_sigkill` (action `sleep 30`, vérifier kill après 5 s)
  - `queue_drops_oldest_when_saturated` (push 1500 events, vérifier 500 droppés)
  - `reentrancy_guard_prevents_cascade` (signal sur `window_created` qui simule un event re-entrant)
  - `filter_by_app_only_matches_target` (signal avec `app="Slack"`, event sur autre app → skip)
  - `invalid_event_in_toml_skipped_with_log`
  - `metrics_counters_increment` (dispatched, dropped, timeouts)
- [ ] T087 [US3] Test acceptance bash `Tests/16-signals-shell-exec.sh` :
  - Crée TOML avec `event="window_created", action="echo $ROADIE_WINDOW_BUNDLE >> /tmp/test-signal.log"`.
  - Reload daemon, lance Calculator → vérifier `/tmp/test-signal.log` contient `com.apple.calculator`.
- [ ] T088 [US3] Test stress robustesse `Tests/16-signals-stress.sh` :
  - Signal léger sur `window_focused`.
  - Boucle `roadie focus next` × 1000 en < 30 s.
  - Vérifier `roadie daemon status | jq .signals.dropped_total` = 0 (pas de drop sous charge raisonnable).
  - Vérifier daemon toujours vivant.
- [ ] T089 [US3] Mettre à jour `implementation.md` avec REX US3.

**Critère de fin US3** : tests acceptance + stress PASS, re-entrancy guard validé, métriques exposées.

---

## Phase 7 — User Story 4 : Insertion directionnelle (P2)

- [ ] T100 [US4] Créer `Sources/RoadieCore/InsertHintRegistry.swift` (~100 LOC) :
  - `@MainActor`, owns `[CGWindowID: InsertHint]`.
  - `set(targetWid:, direction:)`, `consume(parentWid:)`, `handleWindowDestroyed(_:)`, `flushAll(reason:)`.
  - GC `Timer` 30 s purge expirés.
- [ ] T101 [US4] Étendre `Sources/RoadieTiler/LayoutEngine.swift` :
  - Modifier `insert(_ wid:)` pour consulter `hintRegistry.consume(parentWid:)` AVANT l'algo split-largest existant.
  - Si hint trouvé ET tree de `wid` == tree de `targetWid` → applique `direction`. Sinon fallback default.
  - Si hint `direction == .stack` → log info "stack mode not implemented, falling back to default split" (cf. SPEC-017 placeholder).
- [ ] T102 [US4] Étendre `Sources/roadied/CommandRouter.swift` avec `case "window.insert"` :
  - Lit `args["direction"]`, valide.
  - Lit `daemon.registry.focusedWindowID`, error si nil.
  - `daemon.hintRegistry.set(targetWid:, direction:)`.
  - Retour `{hint_target_wid, direction, expires_at}`.
- [ ] T103 [US4] Étendre `Sources/roadie/main.swift` avec verbe `window insert <dir>`.
- [ ] T104 [US4] Étendre `Sources/roadied/main.swift` :
  - Instancier `InsertHintRegistry` avec `ttlMs` depuis `InsertConfig`.
  - Subscribe EventBus `window_destroyed` → `hintRegistry.handleWindowDestroyed(_:)`.
  - Subscribe `tiler_strategy_changed` (à ajouter si pas existant) → `hintRegistry.flushAll(reason: "strategy change")`.
- [ ] T105 [US4] [P] Tests `Tests/RoadieCoreTests/InsertHintRegistryTests.swift` :
  - `consume_within_ttl_returns_hint`
  - `consume_after_ttl_returns_nil`
  - `set_replaces_existing_hint_for_same_wid`
  - `orphan_cleanup_on_target_destroyed`
  - `flush_on_strategy_change`
  - `consume_only_for_same_tree` (multi-display)
- [ ] T106 [US4] Test acceptance bash `Tests/16-insert-directional.sh` :
  - 1 fenêtre A focused.
  - `roadie window insert south`.
  - Lance Calculator → vérifier qu'il apparaît EN BAS de A (frame.y > A.frame.y).
  - Reset, `insert east` → vérifier à droite.
  - Reset, `insert stack` → vérifier fallback split + log info "stack mode not implemented" présent.
- [ ] T107 [US4] (Optionnel V1.1) Implémenter `[insert] show_hint = true` overlay visuel discret. Si non livré V1, juste documenté hors scope dans `implementation.md`.
- [ ] T108 [US4] Mettre à jour `implementation.md` avec REX US4 + scope-out US5 vers SPEC-017.

**Critère de fin US4** : test acceptance PASS, hint consume/orphan/flush validés.

---

## Phase 8 — Polish & cross-cutting

- [ ] T120 [POLISH] Documentation : ajouter section "Rules & signals" au README principal du projet (3-4 paragraphes + lien vers quickstart.md).
- [ ] T121 [POLISH] Documentation : ajouter exemple TOML complet `roadies.toml.example` à la racine du repo pour onboarding nouveaux users.
- [ ] T122 [POLISH] Profiling CPU/RSS sur 1h d'usage avec rules + signals + focus_follows_mouse actifs. Cibles :
  - CPU daemon < 2 % moyen (déjà ~1 % sans SPEC-016)
  - RSS daemon < 80 MB (impact estimé +5-10 MB pour caches regex + queue signals)
- [ ] T123 [POLISH] Audit `/audit 016-yabai-parity-tier1` en mode fix, viser score >= A-.
- [ ] T124 [POLISH] Validation constitution :
  - `find Sources/RoadieCore/Rules Sources/RoadieCore/Signals Sources/RoadieCore/Watchers/MouseFollowFocusWatcher.swift Sources/RoadieCore/MouseInputCoordinator.swift Sources/RoadieCore/InsertHintRegistry.swift Sources/RoadieTiler -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l` → vérifier ≤ 1500 (cible) ou ≤ 2000 (plafond).
  - `nm .build/debug/roadied | grep -E "CGSSetWindow|CGSAddWindow"` → 0 (constitution C').
- [ ] T125 [POLISH] Test régression `Tests/16-no-regression-spec-002.sh` : re-jouer suite SPEC-002 avec rules + signals + focus_follows_mouse actifs. Vérifier 100 % pass (SC-016-11).
- [ ] T126 [POLISH] Test régression `Tests/16-no-regression-spec-014.sh` : idem avec SPEC-014 rail actif. Vérifier que `focus_follows_mouse` ne déclenche pas faux positifs sur le hover du rail.
- [ ] T127 [POLISH] Test régression `Tests/16-no-regression-spec-015.sh` : idem avec MouseDragHandler. Vérifier suspension watcher pendant drag.
- [ ] T128 [POLISH] Mettre à jour `implementation.md` avec REX final (toutes phases).
- [ ] T129 [POLISH] Demander review utilisateur avant merge vers main.
- [ ] T130 [POLISH] Mettre à jour `ADR-006-yabai-feature-gap-analysis.md` (gitignored) :
  - Marquer A1, A2, A4, A5, A6 comme **DONE (SPEC-016)**.
  - Marquer A3 comme **DEFERRED (SPEC-017 placeholder)**.
  - Mettre à jour la priorisation des SPECs ultérieures (B/C).

**Critère de fin Polish** : tous tests verts, audit ≥ A-, doc complète, ADR-006 sync.

---

## Dependencies (DAG)

```
T001..T005 (Setup)
   ↓
T010..T015 (Foundational : Config + EventBus + Logger)
   ↓
   ├──► T020..T025 (US1a — swap)                       ════ MVP P1 partiel
   │       ↓
   │       T030..T040 (US1bc — focus/mouse follows)    ════ MVP P1 partiel
   │       ↓
   │       T050..T059 (US2 — rules)                    ════ MVP P1 partiel
   │       ↓
   │       T080..T089 (US3 — signals)                  ════ MVP P1 complet
   │       ↓
   │       T100..T108 (US4 — insert directional)       ════ V1.1
   │       ↓
   │       T120..T130 (Polish + audit + sync ADR)      ════ V1 final
```

**MVP livrable** : T001 → T089 inclus (Setup + Foundational + US1abc + US2 + US3). US4 (insert) est P2 → optionnel pour MVP.

**Estimation totale** :
| Phase | Sessions estimées |
|---|---|
| Setup (T001-T005) | 0.5 |
| Foundational (T010-T015) | 1 |
| US1a swap (T020-T025) | 1 |
| US1bc mouse follows (T030-T040) | 2 |
| US2 rules (T050-T059) | 3 |
| US3 signals (T080-T089) | 2 |
| US4 insert (T100-T108) | 1 |
| Polish (T120-T130) | 1 |
| **TOTAL** | **~11.5 sessions** |

Sous le plafond 12 (SC-016-08). US5 (stack mode A3) a été scope-out vers SPEC-017 dès Phase 2 plan (cf. plan.md §Summary).

## Estimation parallélisme

Tâches marquées `[P]` peuvent tourner en parallèle :

- **Phase 1** : T002 (mkdir Rules) ‖ T003 (skeleton fichiers) — atomic, 1 commande chacun.
- **Phase 2** : T013 (tests Config) ‖ T014 (tests EventBus) — fichiers tests indépendants.
- **Phase 3** : T023 (tests LayoutEngine) seul.
- **Phase 4** : T037 (tests MouseFollow) ‖ T038 (tests FocusManager) — fichiers tests indépendants.
- **Phase 5** : T056 (tests RuleEngine) seul.
- **Phase 6** : T086 (tests SignalDispatcher) seul.
- **Phase 7** : T105 (tests InsertHint) seul.

Les tâches sur `Sources/RoadieCore/Config.swift`, `Sources/roadied/CommandRouter.swift`, `Sources/roadied/main.swift`, `Sources/roadie/main.swift`, `Sources/RoadieTiler/LayoutEngine.swift` doivent être **séquentielles** (un seul fichier modifié plusieurs fois).

## Risques & mitigations (récap plan §Risks)

| Tâche risquée | Mitigation |
|---|---|
| T020 swap inter-display | Test acceptance dédié `Tests/16-swap.sh` couvre le cas multi-display |
| T032 polling 50 ms CPU | Mesuré en T122 profiling. Fallback CGEventTap documenté dans research R-007 si > 1 % |
| T050 RuleEngine race avec SPEC-011 | Callback synchrone `onWindowAdded` AVANT routing desktop, testé `rule_space_overrides_desktop_default` |
| T081 SignalDispatcher fork bomb | Re-entrancy guard testé `reentrancy_guard_prevents_cascade` + queue cap testé `queue_drops_oldest` |
| T101 InsertHintRegistry leak | GC timer 30 s testé `consume_after_ttl_returns_nil` + cleanup orphelin testé |

## Note de coordination avec SPEC-017 (placeholder)

US5 (stack mode local A3) est **scope-out** mais préservée dans `specs/017-yabai-parity-stack-mode/spec.md`. La commande `roadie window insert stack` est implémentée par SPEC-016 (cf. T101) avec **fallback split par défaut + log info**. Quand SPEC-017 sera livrée, il faudra modifier `LayoutEngine.insert(_:)` pour consommer le hint `stack` correctement (extension du tree avec nœud `Stack`).
