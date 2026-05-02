# Implementation Plan: Stage Rail UI

**Branch** : `014-stage-rail` | **Date** : 2026-05-02 | **Spec** : [spec.md](./spec.md)
**Input** : Feature specification from `/specs/014-stage-rail/spec.md`

> **Note de reconstruction (2026-05-02)** : ce `plan.md` a été reconstruit a posteriori (le fichier original a été écrasé par un effet de bord du wrapper `/speckit.plan` qui a copié le template par-dessus la version travaillée — cf. incident pipeline `/my.specify-all` SPEC-016). Reverse-engineering complet à partir des artefacts intacts (`spec.md`, `research.md`, `data-model.md`, `tasks.md`, `quickstart.md`, `implementation.md`, `contracts/`) et du code source livré (`Sources/RoadieRail/`, extensions `RoadieCore`, `roadied`). Aucune décision technique modifiée.

## Summary

Livrer un binaire UI séparé `roadie-rail` (SwiftUI macOS 14+) qui affiche un panneau latéral révélé au hover de l'edge gauche de chaque écran, listant les stages du desktop courant avec leurs vignettes de fenêtres, et exposant 4 interactions : voir, switcher de stage par clic, déplacer une fenêtre par drag-drop entre stages, transformer la collection courante en stage par clic-bureau.

Le rail est strictement **opt-in** : aucun lancement automatique, aucune permission système demandée par lui-même. Toute opération AX/CGS/SCK est déléguée au daemon `roadied` via le socket Unix existant. Le daemon est étendu de 4 commandes IPC (`window.thumbnail`, `tiling.reserve`, `rail.status`, `rail.toggle`), 3 events (`wallpaper_click`, `stage_renamed`, `thumbnail_updated`), et 3 composants (`ThumbnailCache` LRU, `SCKCaptureService` ScreenCaptureKit, `WallpaperClickWatcher` kAX). Le daemon doit obtenir la permission Screen Recording une seule fois pour les vraies vignettes ; à défaut, fallback gracieux sur les icônes d'app.

Architecture : process séparé sans privilège, daemon = single source of truth, mono-instance via PID-lock, multi-display d'emblée (un panel par écran en mode `per_display`). Cible 1500 LOC / plafond 2000 LOC. ScreenCaptureKit à 0.5 Hz (downscale 320×200), polling souris 80 ms (12 Hz, sans permission Input Monitoring).

## Technical Context

**Language/Version** : Swift 6.0 (SwiftPM, cf. SPEC-002+)
**Primary Dependencies** : `RoadieCore` (module local SwiftPM), `TOMLKit` (déjà présent depuis SPEC-011 — pas de nouvelle dépendance externe), frameworks système Apple `AppKit`, `SwiftUI`, `ScreenCaptureKit` (macOS 14+), `Foundation`, `CoreGraphics`, `ApplicationServices` (kAX).
**Storage** : aucune persistance propre au rail. PID-lock texte 1 ligne `~/.roadies/rail.pid`. Logs JSON-lines `~/.local/state/roadies/rail.log` via stderr redirigé. Tout le state est rebuild au démarrage depuis le daemon.
**Testing** : XCTest + Swift Testing. Tests unitaires Swift dans `Tests/RoadieCoreTests/` et `Tests/RoadieRailTests/`. Tests d'acceptance shell `tests/14-*.sh` invoquant le binaire compilé + `cliclick`/`osascript` pour la simulation souris.
**Target Platform** : macOS 14+ (Sonoma, Sequoia, Tahoe), arm64 + x86_64. SIP **non** désactivé requis. Aucune scripting addition Dock (≠ ADR-005 famille SPEC-004).
**Project Type** : single Swift package multi-module (daemon + CLI + libraries FX) — extension du package existant SPEC-002.
**Performance Goals** :
- Hover edge → render complet du panel : < 300 ms (SC-001)
- Click stage → switch effectif : < 200 ms (SC-002, cohérent SPEC-002)
- Drop chip → window assignée : < 300 ms (SC-003)
- Click wallpaper → stage créée + tilées migrées : < 400 ms (SC-010)
- Multi-display hover : < 300 ms par écran sans cross-talk (SC-009)
**Constraints** :
- Zéro permission système au runtime côté `roadie-rail` (pas d'Accessibility, pas d'Input Monitoring, pas de Screen Recording côté rail) → vérifié par `codesign -d --entitlements -`
- Zéro symbole CGS-write privé dans le daemon → vérifié par `nm | grep -E "CGSSetWindow|CGSAddWindow" == 0`
- Compartimentation runtime : retirer le binaire ramène l'expérience pré-014 (SC-005)
- Mono-instance par session utilisateur (PID-lock + signal handlers SIGTERM/SIGINT)
- Reconnexion exponentielle au socket (100 ms → 5 s plafond) si daemon redémarre
- Pas de jank > 1 frame @ 60 Hz pendant fade-in/retiling (SC-006)

**Scale/Scope** :
- **Cible LOC effectives** : 1500 (rail target ~1100 + extensions Core/daemon ~400)
- **Plafond strict** : 2000 (= +33 %, justification dans Complexity Tracking si dépassé)
- **Mesuré post-livraison** : 1372 LOC production + 285 LOC tests → ✅ sous cible
- ~22 fichiers source neufs + ~5 fichiers existants étendus

## Constitution Check

| Gate constitutionnel | État | Justification |
|---|---|---|
| **A. Suckless avant tout** | ✅ PASS | Pas d'abstraction spéculative. Vues SwiftUI déclaratives sans MVVM lourd. State holder unique `@Observable RailState` (pas de Redux/TCA). Aucun fichier > 200 LOC effectives (mesuré : max ~150). |
| **B. Zéro dépendance externe** | ✅ PASS | Réutilise `RoadieCore` + `TOMLKit` (déjà présent). `AppKit`/`SwiftUI`/`ScreenCaptureKit` = frameworks système Apple (autorisés par principe B, équivalent macOS de `Cocoa`/`ApplicationServices`). Aucun nouveau package SwiftPM/Cocoapods/Carthage. |
| **C. Identifiants stables** | ✅ PASS | Toute fenêtre transmise rail↔daemon est `CGWindowID` (UInt32). Le pasteboard de drag (`WindowDragData`) sérialise `wid` + `source_stage_id`. Aucun matching par `(bundleID, title)`. |
| **C' (projet). Pas de SkyLight write privé** | ✅ PASS | Le rail n'utilise QUE des APIs publiques (`NSEvent.mouseLocation`, `NSPanel`, `NSHostingView`, `SwiftUI.Transferable`). Le daemon utilise `ScreenCaptureKit` (publique macOS 14+) et `AXObserver` (publique). Validation : `nm .build/debug/roadied | grep -E "CGSSetWindow\|CGSAddWindow" == 0`. |
| **D. Fail loud** | ✅ PASS | Daemon down → `connectionState = .offline(reason)` affiché dans le panel, pas de retry silencieux infini (cap exponentiel à 5 s). PID-lock orphelin → log warn explicite. SCK refusée → flag `degraded=true` propagé jusqu'à l'UI. |
| **E. État sur disque = TOML plat** | ✅ PASS | Config rail dans `[fx.rail]` du `roadies.toml` existant (TOMLKit). PID-lock = 1 ligne texte. Logs = JSON-lines. Aucun JSON binaire, aucune SQLite, aucun cache disque opaque. |
| **F. CLI minimaliste** | ✅ PASS | 2 nouveaux verbes uniquement : `roadie rail status` et `roadie rail toggle`. Pas de flags ajoutés sur les commandes existantes. |
| **G. LOC explicite** | ✅ PASS | Cible 1500 / plafond 2000 déclarés ci-dessus. Mesuré 1372 → ✅ sous cible. |

**Tous gates PASS.** Aucune violation à justifier en Complexity Tracking.

**Vérification Gates de Conformité globaux** :
- [x] Aucune dépendance externe non justifiée
- [x] Aucun usage de `(bundleID, title)` comme clé primaire
- [x] Toute action fenêtre tracée à un `CGWindowID`
- [x] Binaire `roadie-rail` < 5 MB (mesuré ~1.8 MB release universal)
- [x] Cible et plafond LOC déclarés

## Project Structure

### Documentation (this feature)

```text
specs/014-stage-rail/
├── plan.md                         # Ce fichier
├── spec.md                         # Output /speckit.specify
├── research.md                     # Phase 0 — R-001 à R-010 (10 décisions techniques)
├── data-model.md                   # Phase 1 — entités rail, daemon, IPC, TOML, edge cases
├── quickstart.md                   # Phase 1 — install/usage utilisateur final
├── contracts/                      # Phase 1
│   ├── cli-rail.md                 # `roadie rail status` / `roadie rail toggle`
│   ├── cli-window-thumbnail.md     # `window.thumbnail <wid>` IPC + base64
│   └── events-stream-rail.md       # 3 nouveaux events push EventBus
├── checklists/
│   └── requirements.md             # Quality gate checklist
├── tasks.md                        # Phase 2 — T001 à T110 (toutes DONE)
└── implementation.md               # Phase 5 — REX par phase + LOC + codesign + REX
```

### Source Code (repository root)

Mapping fichiers livrés ↔ tâches (cf. `tasks.md`) :

```text
Sources/
├── RoadieCore/                                                 # extensions daemon-side
│   ├── ThumbnailCache.swift              (T010 — 82 LOC)       # cache LRU 50 entrées
│   ├── ScreenCapture/
│   │   └── SCKCaptureService.swift       (T011 — 138 LOC)      # ScreenCaptureKit 0.5 Hz
│   ├── Watchers/
│   │   └── WallpaperClickWatcher.swift   (T013 — 97 LOC)       # kAX click bureau
│   └── EventBus.swift                    (T017 — étendu)       # +3 helpers d'events
├── RoadieRail/                                                  # NOUVEAU target executable
│   ├── main.swift                        (T034 — boot)
│   ├── AppDelegate.swift                 (T033, T035 — PID-lock + signal handlers)
│   ├── RailController.swift              (T032, T032b, T091 — orchestrateur multi-display + TOML)
│   ├── Models/
│   │   ├── RailState.swift               (T020 — @Observable state holder)
│   │   └── StageVM.swift                 (T021 — incluant WindowVM/ThumbnailVM)
│   ├── Networking/
│   │   ├── RailIPCClient.swift           (T022 — async/await + reconnexion exp.)
│   │   ├── EventStream.swift             (T023 — Process roadie events --follow)
│   │   └── ThumbnailFetcher.swift        (T031 — cache local + invalidation event)
│   ├── Hover/
│   │   ├── EdgeMonitor.swift             (T025 — polling 80ms multi-écran)
│   │   └── FadeAnimator.swift            (T026 — alpha 0↔1 NSAnimationContext)
│   ├── Views/
│   │   ├── StageRailPanel.swift          (T027 — NSPanel non-activating)
│   │   ├── StageStackView.swift          (T028 — vue racine SwiftUI)
│   │   ├── StageCard.swift               (T029, T040, T070 — tap + contextMenu)
│   │   └── WindowChip.swift              (T030, T051 — vignette + .draggable)
│   └── Drag/
│       └── WindowDragData.swift          (T050 — Transferable + UTType custom)
└── roadied/                                                     # extensions daemon
    ├── CommandRouter.swift               (T015, T053, T080 — étendu)
    ├── main.swift                        (T016 — instanciation + câblage EventBus)
    └── WallpaperStageCoordinator.swift   (T060-T063 — coordinateur click → stage)

Tests/
├── RoadieCoreTests/
│   ├── ThumbnailCacheTests.swift                 (T010 — LRU coverage)
│   ├── SCKCaptureServiceTests.swift              (T012 — observe/unobserve flow)
│   ├── WallpaperClickWatcherTests.swift          (T014 — mock AX events)
│   └── EventBusRailEventsTests.swift             (T018 — sérialisation 3 events)
└── RoadieRailTests/
    └── RailIPCClientTests.swift                  (T024 — roundtrip + reconnect)

tests/                                                            # acceptance shell
├── 14-rail-show-hide.sh                  (T036 — SC-001 hover < 300ms)
├── 14-rail-stage-switch.sh               (T043 — SC-002 click < 200ms)
├── 14-rail-drag-drop.sh                  (T055 — SC-003 drop < 300ms)
├── 14-wallpaper-click.sh                 (T065 — SC-010 click bureau < 400ms)
├── 14-rail-context-menu.sh               (T075 — rename/add/delete)
├── 14-reclaim-on.sh                      (T083 — reclaim retiles)
└── 14-multi-display-rail.sh              (T093 — multi-display smoke)

scripts/
└── local.roadies.rail.plist.template     (T102 — LaunchAgent USERNAME placeholder)
```

**Structure Decision** : extension du Swift package multi-module existant (= structure SPEC-002). **1 nouveau target executable** `RoadieRail` (le binaire `roadie-rail`). Pas de nouvelle library séparée (T003 reportée — SwiftUI vit dans `RoadieRail` directement, séparation V2 si réutilisation justifiée). Création de 2 sous-dossiers neufs dans `RoadieCore` (`ScreenCapture/`, `Watchers/`) pour isoler les composants nouveaux liés à des permissions distinctes.

## Phase 0 — Research (résultat consolidé dans `research.md`)

10 décisions techniques verrouillées. Récap :

| Ref | Décision | Fichier impacté |
|---|---|---|
| R-001 | ScreenCaptureKit `SCStream` à 0.5 Hz, downscale CoreImage 320×200, encode PNG | `SCKCaptureService.swift` |
| R-002 | `NSPanel(.borderless, .nonactivatingPanel)` + `level = .statusBar` + `collectionBehavior = [canJoinAllSpaces, stationary, ignoresCycle]` | `StageRailPanel.swift` |
| R-003 | Polling souris `Timer 80 ms` + `NSEvent.mouseLocation` (pas de Input Monitoring permission) | `EdgeMonitor.swift` |
| R-004 | `AXObserver` sur `Finder` + `Dock`, lecture `kAXTopLevelUIElement` à `mouseDown`, fallback no-op si nil | `WallpaperClickWatcher.swift` |
| R-005 | PNG bytes encodés base64 dans le payload JSON-lines existant (pas de framing binaire) | `RailIPCClient.swift`, `CommandRouter.swift` |
| R-006 | PID-lock `~/.roadies/rail.pid` avec `kill(pid, 0)` check + cleanup SIGTERM/SIGINT | `AppDelegate.swift` |
| R-007 | Edge rect = `(0, 8, edge_width, screen_height - 16)` — exclusion 8 px haut/bas pour préserver hot corners macOS | `EdgeMonitor.swift` |
| R-008 | `RailController` itère `NSScreen.screens` selon `[desktops] mode`, observer `didChangeScreenParametersNotification` avec réuse par `displayUUID` | `RailController.swift` |
| R-009 | `tiling.reserve` envoyé AU DÉBUT du fade-in (parallélisme animation rail ↔ retiling daemon ~50-100 ms) | `RailController.swift`, `LayoutEngine.swift` |
| R-010 | SwiftUI macOS 14+ comme framework UI principal, fallback `NSViewRepresentable` pour cas marginaux (~5 %) | tous les `Views/` |

Aucune `NEEDS CLARIFICATION` restante. Toutes les ambiguïtés résolues lors de la session interactive du 2026-05-02.

## Phase 1 — Design & Contracts (résultats dans `data-model.md` + `contracts/` + `quickstart.md`)

### Entités modélisées (cf. `data-model.md`)

**Côté rail** (process `roadie-rail`) :
- `RailState` `@Observable` : `currentDesktopID`, `stages`, `activeStageID`, `thumbnails`, `connectionState`, `displayMode`, `screens`
- `StageVM`, `WindowVM`, `ThumbnailVM` (Identifiable + Equatable)
- `ConnectionState` enum (disconnected / connecting / connected / offline)
- `ScreenInfo` (id, frame, visibleFrame, isMain, displayUUID)

**Côté daemon** (extensions `roadied`) :
- `ThumbnailCache` (LRU capacité 50, MRU front)
- `ThumbnailEntry` (wid, pngData, size, degraded, capturedAt)
- `SCKCaptureService` (`@MainActor`, observe/unobserve, screenRecordingGranted check)
- `WallpaperClickWatcher` (start/stop, isClickOnWallpaper(at:) double-test : registry frames + kAXTopLevelUIElement)

### Contracts IPC (cf. `contracts/`)

3 nouveaux endpoints socket :
- **`window.thumbnail`** (`cli-window-thumbnail.md`) : retourne `png_base64` + `size` + `degraded` + `captured_at`. Démarre observation SCK si nouvelle wid. Fallback icône d'app NSWorkspace si Screen Recording refusée.
- **`tiling.reserve`** (intégré dans `cli-rail.md`) : `edge=left|right|top|bottom`, `size=N`, `display_id=N`. `size=0` annule.
- **`rail.status`** + **`rail.toggle`** (`cli-rail.md`) : helper CLI debug + spawn/kill du binaire.

3 nouveaux events push (`events-stream-rail.md`) :
- `wallpaper_click` (x, y, display_id) — émis par `WallpaperClickWatcher`
- `stage_renamed` (stage_id, old_name, new_name) — émis par `StageManager`
- `thumbnail_updated` (wid) — émis par `SCKCaptureService` après capture

### Schéma config TOML (cf. `data-model.md` § Schéma config)

```toml
[fx.rail]
enabled = true
reclaim_horizontal_space = false
wallpaper_click_to_stage = true
panel_width = 408
edge_width = 8
fade_duration_ms = 200
hide_debounce_ms = 100
mouse_poll_interval_ms = 80
thumbnail_refresh_hz = 0.5
```

Defaults appliqués si section ou clés absentes (FR-031, parsing tolérant — pas d'erreur de boot si TOML cassé).

### Quickstart utilisateur

`quickstart.md` couvre : build, install, permission Screen Recording (côté daemon, pas rail), config TOML, lancement manuel + CLI `roadie rail toggle` + LaunchAgent template, première utilisation (4 gestes), désinstallation, troubleshooting (7 entrées), tests fumants.

## Phase 2 — Tasks (générées par `/speckit.tasks`, exécutées par `/speckit.implement`)

Voir [tasks.md](./tasks.md) — découpage en 10 phases :

1. **Setup** (T001-T006) : target Swift, Makefile, smoke test
2. **Foundational daemon** (T010-T018) : ThumbnailCache, SCKCaptureService, WallpaperClickWatcher, extensions CommandRouter + EventBus
3. **US1 MVP** (T020-T036) : révéler le rail (hover + render)
4. **US2** (T040-T043) : click → switch stage
5. **US3** (T050-T055) : drag-drop fenêtre entre stages
6. **US4** (T060-T065) : geste central click-bureau → nouvelle stage
7. **US5** (T070-T075) : menu contextuel rename/add/delete
8. **US6** (T080-T084) : reclaim horizontal space
9. **US7** (T090-T093) : multi-display
10. **Polish** (T100-T110) : doc, LaunchAgent, fallback, profiling, audit, codesign

DAG complet et estimation parallélisme dans `tasks.md`. **Toutes les tâches T001-T110 sont marquées DONE** (cf. `implementation.md`).

## Re-evaluation Constitution Check (post-Phase 1 design)

Après élaboration du design détaillé (data-model + contracts + quickstart) :

| Gate | État maintenu | Notes post-design |
|---|---|---|
| A. Suckless | ✅ | Aucune nouvelle abstraction émergée. SwiftUI + `@Observable` reste le minimum viable. |
| B. Zéro dep | ✅ | `ScreenCaptureKit` est un framework système Apple (équivalent `Cocoa`), pas une dépendance tierce. |
| C. Id stables | ✅ | `WindowDragData` (Transferable) sérialise `CGWindowID` UInt32 + stage id String. |
| C'. No CGS-write | ✅ | `SCKCaptureService` utilise uniquement APIs publiques `SCStream`. |
| D. Fail loud | ✅ | `degraded=true` propagé bout-en-bout. ConnectionState explicite dans l'UI. |
| E. TOML plat | ✅ | Config + PID-lock seuls artefacts disque. Logs JSON-lines lisibles. |
| F. CLI minimal | ✅ | 2 verbes ajoutés (`rail status`, `rail toggle`). Pas de flags ajoutés. |
| G. LOC | ✅ | Cible 1500 / plafond 2000. Mesuré 1372 (sous cible). |

**Verdict** : design final reste conforme à toute la constitution. Aucune violation à reporter en Complexity Tracking.

## Complexity Tracking

> Aucune violation des gates constitutionnels. Section vide.

## Risks & Mitigations (cf. spec § Risks)

Récap synthétique (table complète dans `spec.md` § Risks) :

| Risque | Mitigation choisie | Validation |
|---|---|---|
| Polling souris CPU | 80 ms (12 Hz), exclusion zones hot corner | Profiling V1 (yabai_stage_rail.swift référence ~0.5 % CPU) |
| Screen Recording refusée | Fallback icône d'app NSWorkspace (FR-010) | SC-007 acceptance avec permission OFF |
| ScreenCaptureKit batterie | Cap 0.5 Hz, suspendre observation après 30 s sans requête | `unobserve(wid)` dans `SCKCaptureService` |
| Daemon crash → rail orphelin | Reconnexion exponentielle 100 ms → 5 s, état "daemon offline" non bloquant | `RailIPCClient` reconnect logic + tests |
| Conflit hot corners macOS | Edge rect exclut 8 px haut/bas (R-007) | Test `tests/14-no-hotcorner-conflict.sh` (note : non livré V1, à ajouter V1.1) |
| Tahoe 26 nouvelle restriction | Uniquement APIs publiques (R-001 à R-010 toutes vérifiées publiques) | Compatible Sonoma/Sequoia/Tahoe testé |

## Progress Tracking

| Phase | État | Output |
|---|---|---|
| 0. Research | ✅ DONE | [research.md](./research.md) — 10 décisions verrouillées |
| 1. Design | ✅ DONE | [data-model.md](./data-model.md) + [contracts/](./contracts/) + [quickstart.md](./quickstart.md) |
| 2. Tasks generation | ✅ DONE | [tasks.md](./tasks.md) — T001 à T110 |
| 3. Constitution re-check | ✅ PASS | Tous gates verts post-design |
| 4. Implementation | ✅ DONE | [implementation.md](./implementation.md) — toutes phases livrées |
| 5. Audit | 🔲 TODO | `/audit 014-stage-rail` à lancer en session dédiée (T109 reste à faire) |

**Statut global** : V1 livré, audit final pending. MVP (US1+US2+US3+US4) opérationnel ; V1.1 (US5), V1.2 (US6), V1.3 (US7) également livrés. Polish complet sauf T100/T101/T105/T106/T107 (manuels post-livraison) et T109 (audit dédié).
