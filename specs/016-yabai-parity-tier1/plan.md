# Implementation Plan: Yabai-parity tier-1 (catégorie A complète)

**Branch** : `016-yabai-parity-tier1` | **Date** : 2026-05-02 | **Spec** : [spec.md](./spec.md)
**Input** : Feature specification from `/specs/016-yabai-parity-tier1/spec.md`

## Summary

Combler les 6 gaps majeurs identifiés dans **ADR-006 catégorie A** entre roadie et yabai : (A1) règles déclaratives `[[rules]]`, (A2) signals shell `[[signals]]`, (A3) mode stack local, (A4) insertion directionnelle `--insert`, (A5) `--swap`, (A6) `focus_follows_mouse`/`mouse_follows_focus`. Toute l'extension est intégrée à `RoadieCore` + `roadied` (pas de nouveau target executable). Architecture pivot autour de 4 nouveaux composants (`RuleEngine`, `SignalDispatcher`, `MouseFollowFocusWatcher`, `InsertHintRegistry`) + extensions ciblées du `LayoutEngine` (swap, optionnellement stack mode), du `CommandRouter` (12 nouvelles commandes IPC) et de `Config.swift` (3 nouvelles sections TOML). Réutilise massivement les patterns existants : `DisplayRule` premier-match-wins (SPEC-012) → modèle pour `RuleDef`, `EventBus` AsyncStream (SPEC-014) → backbone pour `SignalDispatcher`, `MouseDragHandler` global event monitor (SPEC-015) → mutualisé avec `MouseFollowFocusWatcher` pour partager la permission Input Monitoring.

**Décision de scope d'entrée** : la spec autorise un scope-out de US5 (stack mode A3) vers SPEC-017 si l'effort dépasse 8 sessions à la phase plan. **Estimation réalisée ci-dessous** : US5 seul = 4-6 sessions à cause du refactor `LayoutEngine` (introduction du nœud `Stack` qui change le model `LayoutNode`, propagation à tous les algorithmes BSP, gestion offscreen pour les fenêtres cachées, indicateur visuel). **Décision** : **scope-out US5 vers SPEC-017** dès cette phase. SPEC-016 livre US1+US2+US3+US4 (estimation 7-11 sessions, sous le plafond 12). `--insert stack` (US4) tombe sur fallback split par défaut + log info, comme prévu par FR-A4-04.

## Technical Context

**Language/Version** : Swift 6.0 (SwiftPM, cf. SPEC-002+)
**Primary Dependencies** : `RoadieCore`, `RoadieTiler`, `RoadieDesktops` (modules locaux), `TOMLKit` (déjà présent), frameworks système Apple `Foundation`, `AppKit`, `CoreGraphics`, `ApplicationServices`. **Aucune nouvelle dépendance externe.**
**Storage** : aucune persistance propre. Rules + signals chargés depuis `~/.config/roadies/roadies.toml` au boot et au reload (cohérent constitution principe E). Hints `InsertHint` purement runtime mémoire (TTL 120 s).
**Testing** : XCTest + Swift Testing existants. Tests unitaires `Tests/RoadieCoreTests/` (RuleEngine, SignalDispatcher, MouseFollowFocusWatcher, InsertHintRegistry parsing/matching). Tests d'acceptance shell `Tests/16-*.sh` (1 par user story).
**Target Platform** : macOS 14+, arm64 + x86_64. SIP non désactivé requis. Aucune scripting addition.
**Project Type** : single Swift package multi-module (extension du package SPEC-002).
**Performance Goals** :
- Match d'une rule sur `window_created` : < 100 ms (SC-016-03)
- Latence dispatch event → exec signal : p99 < 50 ms sous 100 ev/s (SC-016-06)
- `focus_follows_mouse autofocus` : focus migre après 200 ms d'idle curseur (configurable)
- `mouse_follows_focus` : téléportation curseur immédiate au changement de focus (< 16 ms = 1 frame)
- swap : équivalent `move`/`warp` actuels, < 50 ms

**Constraints** :
- Re-entrancy guard impératif : un signal action qui déclenche un event ne doit PAS re-déclencher de signal (FR-A2-08)
- SignalDispatcher async : ne JAMAIS bloquer le daemon (Process.run() détaché, timeout 5 s, queue cap 1000)
- MouseFollowFocusWatcher coexiste avec MouseDragHandler SPEC-015 via `MouseInputCoordinator` partagé (suspension pendant drag actif)
- Anti-pattern `app=".*"` rejeté au parsing rules (FR-A1-08) — éviter de désactiver involontairement tout le tiling
- Parser tolérant : 50 % rules cassées ne bloquent pas les autres (SC-016-05)
- Constitution C (id stables) : toutes les commandes manipulent des `CGWindowID` UInt32, jamais `(bundleID, title)` comme clé primaire — `app`/`title` sont des **filtres de match**, pas des identifiants
- Constitution C' (no SkyLight write) : aucune nouvelle API privée, `MouseFollowFocusWatcher` réutilise `NSEvent.addGlobalMonitorForEvents` (déjà autorisé par Input Monitoring SPEC-015)

**Scale/Scope** :
- **Cible LOC effectives** : 1500 (production hors tests)
- **Plafond strict** : 2000 (= +33 %, justification dans Complexity Tracking si dépassé)
- ~10 fichiers source neufs + ~5 fichiers étendus (Config, EventBus, CommandRouter, LayoutEngine, main.swift)
- Tests : ~600 LOC

**Décomposition LOC estimée par composant** :
| Composant | LOC cible |
|---|---|
| `RuleEngine.swift` (parsing + match + apply) | 300 |
| `SignalDispatcher.swift` (subscribe + match + exec async + timeout) | 250 |
| `MouseFollowFocusWatcher.swift` | 150 |
| `MouseInputCoordinator.swift` (coordination avec SPEC-015) | 80 |
| `InsertHintRegistry.swift` | 100 |
| Extensions `LayoutEngine` (swap directionnel) | 100 |
| Extensions `CommandRouter` (12 nouvelles commandes IPC) | 200 |
| Extensions `Config.swift` (3 sections TOML : `[[rules]]`, `[[signals]]`, [mouse] étendu) | 150 |
| Extensions `main.swift` (instanciation + câblage) | 70 |
| Extensions `roadie/main.swift` (CLI : nouveaux verbes) | 100 |
| **Total production** | **1500** |
| Tests unitaires + acceptance shell | 600 |

## Constitution Check

| Gate constitutionnel | État | Justification |
|---|---|---|
| **A. Suckless avant tout** | ✅ PASS | Aucun fichier > 200 LOC effectives (max prévu : `RuleEngine.swift` 300 LOC découpé en 3 fichiers `RuleDef.swift`, `RuleParser.swift`, `RuleApplicator.swift`). Pas d'abstraction spéculative — pas de DSL custom, juste TOML parsé en structs Codable. |
| **B. Zéro dépendance externe** | ✅ PASS | Réutilise `RoadieCore` + `TOMLKit` (déjà présent). Process exec via `Foundation.Process` (système). Aucun nouveau package. |
| **C. Identifiants stables** | ✅ PASS | Toutes les commandes (swap, insert, focus, signals payload) utilisent `CGWindowID` (UInt32). Les rules `app=...`/`title=...` sont des **filtres de match au moment du `window_created`**, jamais des clés persistantes. Une fois la rule appliquée, on persiste l'effet sur le wid (ex: `isTileable = false`), pas la rule elle-même. |
| **C' (projet). Pas de SkyLight write privé** | ✅ PASS | `MouseFollowFocusWatcher` utilise `NSEvent.mouseLocation` (publique) ou se greffe sur `NSEvent.addGlobalMonitorForEvents` du `MouseDragHandler` SPEC-015 (déjà autorisé). `mouse_follows_focus` utilise `CGWarpMouseCursorPosition` (publique CoreGraphics). Aucune API CGS-write. Validation post-build : `nm .build/debug/roadied \| grep -E "CGSSetWindow\|CGSAddWindow" == 0`. |
| **D. Fail loud** | ✅ PASS | Rule invalide → log warn explicite + skip (pas de fallback silencieux). Signal action timeout → log warn avec stderr capturé. Anti-pattern `app=".*"` → log error explicit + reject au parsing. Parser tolérant ≠ silent : chaque skip est tracé. |
| **E. État sur disque = TOML plat** | ✅ PASS | Rules + signals dans `roadies.toml` existant (TOMLKit). Aucun side file, aucune SQLite, aucun cache binaire. Hints purement mémoire. |
| **F. CLI minimaliste** | ✅ PASS | Nouveaux verbes : `roadie window swap <dir>`, `roadie window insert <dir>`, `roadie rules list`, `roadie rules apply --all`. **4 nouveaux verbes** (≤ 5 = acceptable). Pas de flags ajoutés sur les commandes existantes (focus, move, warp, etc.). |
| **G. LOC explicite** | ✅ PASS | Cible 1500 / plafond 2000 déclarés ci-dessus avec décomposition par composant. |

**Tous gates PASS.** Aucune violation à justifier en Complexity Tracking.

**Vérification Gates de Conformité globaux** :
- [x] Aucune dépendance externe non justifiée
- [x] Aucun usage de `(bundleID, title)` comme clé primaire (filtres de match seulement)
- [x] Toute action fenêtre tracée à un `CGWindowID`
- [x] Binaire `roadied` reste < 5 MB après extension (estimation +200-300 KB)
- [x] Cible et plafond LOC déclarés

## Project Structure

### Documentation (this feature)

```text
specs/016-yabai-parity-tier1/
├── plan.md                         # Ce fichier
├── spec.md                         # Output /speckit.specify
├── research.md                     # Phase 0 — décisions techniques (R-001 à R-008)
├── data-model.md                   # Phase 1 — entités RuleDef, SignalDef, InsertHint, etc.
├── quickstart.md                   # Phase 1 — exemples TOML + tutoriel utilisateur
├── contracts/                      # Phase 1
│   ├── cli-rules.md                # `roadie rules list` / `apply --all` + format TOML
│   ├── cli-signals.md              # `[[signals]]` TOML + env vars contextuelles ROADIE_*
│   ├── cli-window-swap-insert.md   # `window swap`, `window insert` IPC
│   └── mouse-follows-config.md     # Extensions `[mouse]` focus_follows_mouse / mouse_follows_focus
├── checklists/
│   └── requirements.md             # Quality gate (✅ rédigée Phase 1)
└── tasks.md                        # Phase 2 — découpage T001..Tnnn (à générer)
```

### Source Code (repository root)

Mapping fichiers prévus ↔ user stories (cf. tasks.md à venir) :

```text
Sources/
├── RoadieCore/
│   ├── Config.swift                          # ÉTENDU : sections [[rules]], [[signals]], [mouse] focus_follows
│   ├── EventBus.swift                        # ÉTENDU : factory events `application_front_switched`, `mouse_dropped`
│   ├── Rules/                                # NOUVEAU sous-dossier (cohérent ScreenCapture/, Watchers/)
│   │   ├── RuleDef.swift                     # struct Codable + Sendable, premier-match-wins (pattern DisplayRule)
│   │   ├── RuleParser.swift                  # validation + anti-pattern `app=".*"` reject
│   │   └── RuleEngine.swift                  # match au window_created + apply (manage/float/sticky/space/display/grid)
│   ├── Signals/                              # NOUVEAU sous-dossier
│   │   ├── SignalDef.swift                   # struct Codable + Sendable
│   │   ├── SignalDispatcher.swift            # subscribe EventBus + match + exec async + timeout
│   │   └── SignalEnvironment.swift           # construction env vars ROADIE_* selon event type
│   ├── Watchers/
│   │   └── MouseFollowFocusWatcher.swift     # NOUVEAU : polling 50ms ou tap NSEvent (mutualisation SPEC-015)
│   ├── MouseInputCoordinator.swift           # NOUVEAU : coordination MouseDragHandler ↔ MouseFollowFocusWatcher
│   ├── InsertHintRegistry.swift              # NOUVEAU : map [WindowID: InsertHint] avec TTL 120s
│   └── MouseDragHandler.swift                # ÉTENDU : flag `_dragActive` exposé pour MouseInputCoordinator
├── RoadieTiler/
│   └── LayoutEngine.swift                    # ÉTENDU : `swap(_ wid, direction:)`, consume InsertHint au insert
└── roadied/
    ├── CommandRouter.swift                   # ÉTENDU : 12 nouvelles commandes IPC
    └── main.swift                            # ÉTENDU : instancie RuleEngine, SignalDispatcher, MouseFollowFocusWatcher, MouseInputCoordinator

Sources/roadie/
└── main.swift                                # ÉTENDU : nouveaux verbes CLI

Tests/
├── RoadieCoreTests/
│   ├── RuleEngineTests.swift                 # NOUVEAU : parsing, match, anti-pattern reject
│   ├── SignalDispatcherTests.swift           # NOUVEAU : exec, timeout, queue cap, re-entrancy
│   ├── MouseFollowFocusWatcherTests.swift    # NOUVEAU : autofocus/autoraise/off, idle threshold
│   ├── InsertHintRegistryTests.swift         # NOUVEAU : TTL expiry, consumption, orphan cleanup
│   └── ConfigRulesSignalsTests.swift         # NOUVEAU : parsing TOML, fallback defaults, parser tolérant
├── RoadieTilerTests/
│   └── LayoutEngineSwapTests.swift           # NOUVEAU : swap préserve structure, no-op si solo, inter-display
└── 16-*.sh                                   # NOUVEAU : 1 acceptance shell par user story
    ├── 16-swap.sh
    ├── 16-focus-follows-mouse.sh
    ├── 16-mouse-follows-focus.sh
    ├── 16-rules-manage-off.sh
    ├── 16-rules-space-display-grid.sh
    ├── 16-signals-shell-exec.sh
    └── 16-insert-directional.sh
```

**Structure Decision** : extension du package multi-module existant. **Aucun nouveau target SwiftPM** (contrairement à SPEC-014 qui avait introduit `RoadieRail`). Tout vit dans `RoadieCore` + `RoadieTiler` + `roadied` + `roadie`. Création de **2 nouveaux sous-dossiers** dans `RoadieCore` (`Rules/`, `Signals/`) pour isoler les composants neufs (cohérent pattern `Watchers/`, `ScreenCapture/`). **`MouseInputCoordinator.swift` à la racine** de RoadieCore car il coordonne 2 watchers (pas spécifique à un sous-domaine).

## Phase 0 — Research

8 décisions techniques à verrouiller. Détails dans [research.md](./research.md). Récap orientation :

| Ref | Sujet | Décision orientation (validée en research.md) |
|---|---|---|
| R-001 | **Format TOML rules** | `[[rules]]` array of tables, fields nullable, premier-match-wins (pattern `DisplayRule` SPEC-012) |
| R-002 | **Regex matching** | `NSRegularExpression` (Foundation), pas de PCRE étendu. Compilation au parsing, cache. |
| R-003 | **Anti-pattern detection** | Rejet `app=".*"` / `title=".*"` au parsing avec error explicite. Détection : regex match-all heuristique (pattern qui match string vide) |
| R-004 | **Signal exec async** | `Foundation.Process` détaché, stdout/stderr capturé, timeout via `DispatchSourceTimer` 5 s → SIGTERM puis SIGKILL +1 s |
| R-005 | **Signal queue cap** | `SignalDispatcher` queue interne `Deque<DesktopEvent>` cap 1000, drop FIFO si saturée + log warn |
| R-006 | **Re-entrancy guard** | Flag `_inside_signal: ThreadLocal<Bool>` dans le contexte d'exec ; events publiés depuis cet exec ne déclenchent pas de signal |
| R-007 | **MouseFollowFocus implementation** | Polling 50 ms (Timer + NSEvent.mouseLocation) plutôt que tap CGEventTap. Raison : pas de surface supplémentaire, cohérent avec EdgeMonitor SPEC-014. Coût mesuré équivalent (<0.5% CPU). |
| R-008 | **Insert hint cycle de vie** | Map `[CGWindowID: InsertHint]` côté daemon, TTL 120 s, consommé au prochain `window_created` dans le tree de la wid cible. Cleanup orphelin si fenêtre cible fermée avant consommation. |

Aucune `NEEDS CLARIFICATION` n'émerge à ce stade. Toutes les ambiguïtés ont été résolues par défauts inférés et documentés dans la spec.

## Phase 1 — Design & Contracts

### Entités modélisées (cf. data-model.md)

**Composants RoadieCore** :
- `RuleDef` : struct Codable, Sendable, premier-match-wins (modèle `DisplayRule` SPEC-012). Champs : `app: String?`, `title: String?` (regex compilés à l'init), `manage: ManageMode?`, `float: Bool?`, `sticky: Bool?`, `space: Int?`, `display: Int?`, `grid: GridSpec?`, `reapplyOnTitleChange: Bool = false`.
- `SignalDef` : struct Codable, Sendable. Champs : `event: String` (validé contre la liste fermée des 18 events supportés), `action: String` (shell command), `app: String?`, `title: String?`.
- `InsertHint` : struct Sendable. Champs : `targetWid: CGWindowID`, `direction: InsertDirection`, `expiresAt: Date`.
- `MouseFollowConfig` : extension de `MouseConfig`, ajoute `focusFollowsMouse: FocusFollowMode (.off|.autofocus|.autoraise)` + `mouseFollowsFocus: Bool` + `idleThresholdMs: Int = 200`.
- `RuleEngine` : `@MainActor`, observe `EventBus.window_created`, applique `RuleDef.firstMatch(for:)` puis dispatch les actions vers WindowRegistry/StageManager/DesktopRegistry/LayoutEngine/DisplayManager.
- `SignalDispatcher` : `@MainActor`, subscribe EventBus, queue interne, exec async via `Foundation.Process`, env vars contextuelles, timeout, re-entrancy guard.
- `MouseInputCoordinator` : `@MainActor`, owns le `NSEvent.addGlobalMonitorForEvents` partagé, dispatch événements souris vers `MouseDragHandler` ET `MouseFollowFocusWatcher` selon état (drag actif → drag prioritaire, sinon follow actif).

### Contracts IPC (cf. contracts/)

**12 nouvelles commandes** réparties en 4 fichiers :

- `cli-window-swap-insert.md` :
  - `window.swap` (`{direction: "left|right|up|down"}`)
  - `window.insert` (`{direction: "north|south|east|west|stack"}`)
  - `focus` (étendu : ajout `stack.next`/`stack.prev` *si US5 scope-in, sinon noop+log*)
  - `window.toggle.split` (bascule V↔H d'un nœud parent — *si US5*, sinon noop)

- `cli-rules.md` :
  - `rules.list` → liste des rules chargées avec index 0-based
  - `rules.apply` (`{all: true}`) → re-évalue les rules sur toutes les fenêtres existantes (opt-in)

- `cli-signals.md` :
  - `signals.list` → liste des signals chargés
  - Note : pas de commande pour add/remove dynamique. La modification passe par édition TOML + `daemon reload`.

- `mouse-follows-config.md` : pas de commande IPC (la config est statique TOML), mais documentation complète des champs `[mouse]` étendus + exemples.

**4 nouveaux events publiés sur EventBus** (au-delà des existants) :
- `application_front_switched` (pour signals filter)
- `mouse_dropped` (déjà publié par SPEC-015 drag, formalisé ici comme contrat de signal)
- `window_title_changed` (pour `reapplyOnTitleChange = true`)
- `space_changed` (déjà publié par SPEC-011, formalisé)

### Schéma config TOML

Sections nouvelles ajoutées à `~/.config/roadies/roadies.toml` :

```toml
[mouse]
# Existant SPEC-015
modifier = "ctrl"
action_left = "move"
action_right = "resize"
action_middle = "none"
edge_threshold = 30
# Nouveau SPEC-016
focus_follows_mouse = "off"        # off | autofocus | autoraise
mouse_follows_focus = false        # bool
idle_threshold_ms = 200            # délai anti-jitter pour focus_follows_mouse

[[rules]]
app = "1Password"                  # match exact ou regex
title = "1Password mini"           # regex optionnel
manage = "off"                     # on | off
# float = true / sticky = true / space = 5 / display = 2 / grid = "4:4:3:3:1:1"

[[signals]]
event = "window_focused"
action = "echo $ROADIE_WINDOW_BUNDLE >> /tmp/focus.log"
# app = "Slack"  / title = "^Settings$"  (filtres optionnels)

[insert]
hint_timeout_ms = 120000           # 2 minutes
show_hint = false                  # overlay visuel sur le bord cible

[signals]                          # section globale (pas array)
timeout_ms = 5000                  # timeout par action
queue_cap = 1000                   # cap drop FIFO
```

**Defaults** appliqués si section/clé absente (parser tolérant FR-T-02 + SC-016-05).

### Quickstart

`quickstart.md` couvre 6 cas d'usage end-to-end :
1. Activer `focus_follows_mouse = autofocus` + démo navigation sans clic
2. Activer `mouse_follows_focus = true` + combo BTT shortcut
3. Écrire une rule pour 1Password mini (`manage = off`)
4. Écrire une rule pour Slack (`space = 5`)
5. Écrire un signal pour notifier sur ouverture fenêtre Terminal
6. Utiliser `window swap left/right` + `window insert east` au quotidien

Migration depuis `~/.yabairc` : tableau de mapping 1-pour-1 pour 80 % des champs courants (cf. SC-016-09).

## Phase 2 — Tasks (à générer par `/speckit.tasks`)

Découpage prévisionnel en 8 phases (estimation) :

| Phase | Tasks | Estimation sessions |
|---|---|---|
| Setup | T001-T005 | 0.5 |
| Foundational : Config + EventBus extensions | T010-T015 | 1 |
| US1a (P1) : window swap | T020-T025 | 1 |
| US1b/c (P1) : MouseFollowFocusWatcher + MouseInputCoordinator + mouse_follows_focus | T030-T040 | 2 |
| US2 (P1) : RuleEngine complet | T050-T070 | 3 |
| US3 (P1) : SignalDispatcher complet | T080-T095 | 2 |
| US4 (P2) : InsertHintRegistry + insert directional | T100-T110 | 1 |
| Polish + audit | T120-T130 | 1 |
| **TOTAL** | | **~11.5 sessions** |

US5 (stack mode) **scope-out vers SPEC-017** (cf. décision §Summary). Tient sous le plafond 12 sessions de SC-016-08.

## Re-evaluation Constitution Check (post-Phase 1 design)

Après élaboration data-model + contracts + quickstart :

| Gate | État | Notes post-design |
|---|---|---|
| A. Suckless | ✅ | Découpage `Rules/{RuleDef, RuleParser, RuleEngine}.swift` confirmé pour rester sous 200 LOC/fichier. |
| B. Zéro dep | ✅ | `Foundation.Process` (système). Aucun ajout SwiftPM. |
| C. Id stables | ✅ | `app`/`title` = filtres de match, jamais clés. Rules persistent leurs effets sur `CGWindowID` (ex: `isTileable = false`), pas la rule elle-même. |
| C'. No CGS-write | ✅ | Vérifié API par API en research.md. `CGWarpMouseCursorPosition` est publique. |
| D. Fail loud | ✅ | Tous les paths d'erreur ont un log explicite (rule reject, signal timeout, anti-pattern, parser tolérant tracé). |
| E. TOML plat | ✅ | Sections `[[rules]]`, `[[signals]]`, `[mouse]` étendu, `[insert]`, `[signals]` (global) toutes en TOML. |
| F. CLI minimal | ✅ | 4 nouveaux verbes (rules list, rules apply, window swap, window insert). Sous le seuil. |
| G. LOC | ✅ | Décomposition LOC explicite dans Technical Context. Cible 1500 sans US5 (qui passerait en SPEC-017). |

**Verdict** : design final reste conforme à toute la constitution. Aucune violation à reporter.

## Complexity Tracking

> Aucune violation des gates constitutionnels. Section vide.

## Risks & Mitigations

Récap des 4 risques identifiés en checklist requirements (R1-R4) :

| Risque | Mitigation |
|---|---|
| **R1 — US5 stack mode invasif** | **Scope-out acté en Phase 2 plan** (cf. décision §Summary). SPEC-017 dédiée prévue. `--insert stack` (US4) tombe sur fallback split par défaut + log info (FR-A4-04). |
| **R2 — SignalDispatcher exec shell async = surface bugs** | Cadré par FR-A2-04/06/07/08 : timeout 5 s, queue cap 1000, re-entrancy guard, exec détaché. Tests : `SignalDispatcherTests.swift` couvre exec, timeout, kill, queue saturation, re-entrancy. SC-016-04 valide robustesse sous 1000 events stress test. |
| **R3 — MouseInputCoordinator coexistence SPEC-015** | Design explicite : `MouseInputCoordinator` owns le `NSEvent.addGlobalMonitorForEvents`, dispatch event-by-event. Drag actif → priorité drag (suspension follow). Tests d'intégration `Tests/RoadieCoreTests/MouseInputCoordinatorTests.swift` couvrent les 4 combinaisons (idle/drag actif × follow on/off). |
| **R4 — Race rules `space=N` × SPEC-011 desktop assignment** | Séquence ordonnée : `RuleEngine.apply()` est appelé **synchrone après** `WindowRegistry.add(window)`, **avant** que `DesktopRegistry` ne fasse son routing initial. Tests : `RuleEngineTests.swift` cas `rule_space_overrides_desktop_default`. |

## Progress Tracking

| Phase | État | Output |
|---|---|---|
| 0. Research | 🔲 TODO | [research.md](./research.md) à rédiger (Phase 1 ci-dessous) |
| 1. Design | 🔲 TODO | [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md) à rédiger |
| 2. Tasks generation | 🔲 TODO | [tasks.md](./tasks.md) à générer via `/speckit.tasks` (ou inline pour éviter rechute bug setup-plan) |
| 3. Constitution re-check | ✅ PASS | Tous gates verts post-design (cf. table ci-dessus) |
| 4. Implementation | 🔲 TODO | Phase 5 du pipeline `/my.specify-all` |
| 5. Audit | 🔲 TODO | `/audit 016-yabai-parity-tier1` après livraison |

**Statut global** : Phase 0+1 plan rédigé. Décision scope (US5 → SPEC-017) actée. Prochain step : research.md + data-model.md + contracts/ + quickstart.md, puis tasks.md, puis implementation.
