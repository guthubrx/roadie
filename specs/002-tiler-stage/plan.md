# Implementation Plan: Tiler + Stage Manager modulaire (roadies)

**Branch**: `002-tiler-stage` | **Date**: 2026-05-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-tiler-stage/spec.md`

## Summary

Window manager macOS modulaire en Swift composé de quatre modules : Core (daemon AX, registry, server socket), Tiler (protocole + impl BSP + Master-Stack), StagePlugin (groupes opt-in masquage par coin), CLI (client socket). Inspiré yabai et AeroSpace mais sans SIP désactivé. Click-to-focus fiable via `kAXApplicationActivatedNotification` (différenciateur vs AeroSpace). V1 ~2 500 LOC, single-monitor strict.

## Technical Context

**Language/Version** : Swift 5.9+ (Xcode toolchain), Swift Concurrency (`@MainActor`, `Task`)
**Primary Dependencies** :
- Frameworks système : `Cocoa`, `ApplicationServices`, `CoreGraphics`, `Network` (NWListener), `IOKit.hid` (IOHIDRequestAccess pour Input Monitoring perm), `Carbon` (GetProcessForPID via @_silgen_name)
- Framework privé linké : `/System/Library/PrivateFrameworks/SkyLight.framework` (link via `Package.swift` linkerSettings) pour `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` — bring-to-front inter-app fiable Sonoma+, pattern industrie WM macOS, **ne nécessite PAS SIP désactivé**
- API privées stables (déclarées via `@_silgen_name`) : `_AXUIElementGetWindow` (cf. SPEC-001), `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, `GetProcessForPID`
- Tierce part acceptée : `TOMLKit` pour parsing config (~30 KB ajoutés au binaire). Alternative parser maison reportée en V2.
**Storage** :
- Config : `~/.config/roadies/roadies.toml` (lecture seule daemon)
- État stages : `~/.config/roadies/stages/<name>.toml` (écriture daemon)
- Socket : `~/.roadies/daemon.sock` (Unix domain)
- Logs : `~/.local/state/roadies/daemon.log` (rotation simple, 10 MB max)
**Testing** :
- Tests unitaires Swift via `XCTest` pour les composants isolés (TreeNode, BSP layout, parser TOML)
- Tests d'intégration en script shell contre le daemon en cours d'exécution
- Tests d'acceptation manuels documentés (catégories : tiling auto, click-to-focus apps spécifiques, bascule stage)
- Pas de CI macOS (impossible sans display + Accessibility) → tests locaux uniquement
**Target Platform** : macOS 14 (Sonoma) minimum, prioritaire 15 (Sequoia) et 26 (Tahoe). Universal binary x86_64 + arm64.
**Project Type** : Single project — Swift Package Manager avec deux exécutables (`roadied` daemon, `roadie` CLI) et plusieurs targets bibliothèques.
**Performance Goals** :
- Tiling d'une nouvelle fenêtre < 200 ms (SC-001)
- Click-to-focus sync < 100 ms (SC-002)
- Bascule stage < 500 ms pour 5 fenêtres (SC-003)
- Démarrage daemon à froid < 1 s (objectif implicite)
**Constraints** :
- Daemon < 5 MB, CLI < 500 KB (SC-004) — *daemon : 1.6 MB ✓ ; CLI : 1.4 MB ⚠️ TOMLKit transitif à refactorer*
- 0 fuite mémoire sur 100 cycles (SC-008)
- **LOC Swift cible 2 000 effectives, plafond strict 4 000** (cf. principe G' constitution-002 + principe G constitution.md). État actuel : **~ 2 600 effectives** ✓ (marge ~35 %, croissance Phase 8 + Phase 9 + Phase 10 maîtrisée — modules ajoutés : MouseRaiser, PeriodicScanner, DragWatcher, WindowActivator, OuterGaps)
- Mesure de référence : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`
- Pas de SIP désactivé (FR-005)
- Sortie standard daemon en JSON-lines pour grep/jq friendly
**Scale/Scope** :
- 1 utilisateur, 1 machine, 1 écran principal
- Jusqu'à 50 fenêtres tilées simultanément
- Jusqu'à 10 stages
- Apps : couvrir l'ensemble des bundle IDs courants (Electron, AppKit, Catalyst, JetBrains, Java, browsers, terminals)

## Constitution Check

*GATE: Doit passer avant Phase 0. Re-vérifié après Phase 1.*

### Constitution Globale (`@~/.speckit/constitution.md`)

| Gate | Statut | Justification |
|---|---|---|
| Article I — Documentation française | PASS | spec/plan/research/data-model/contracts/quickstart en français |
| Article II — Co-pilote idéation | PASS | Mode autonome `/my.specify-all`-like |
| Article III — Processus SpecKit | PASS | specify → plan → tasks → implement enclenché |
| Article IV — Circuit breaker (max 3 tentatives) | PASS | Sera surveillé en Phase Implement |
| Article V — Anti scope-creep | PASS | Out of Scope V1 strict (10 items exclus) |
| Article VII — ADR | PARTIEL | À créer pour les 3 décisions architecturales clés (AX par app, arbre N-aire, masquage en coin) |
| Article VIII — Debug forensic | N/A | S'appliquera en Phase Implement |
| Article IX — Recherche préalable | PASS | research.md de 820 lignes produit avant cette phase |

### Constitution Projet (`.specify/memory/constitution.md` SPEC-001)

L'ancienne constitution projet ciblait SPEC-001 (suckless mono-fichier). Pour SPEC-002, le scope a évolué — le mono-fichier n'est plus possible (≥ 2 000 LOC). Les principes restent valides en esprit :

| Principe | Adapté V2 | Justification |
|---|---|---|
| A. Suckless avant tout | Adapté : multi-fichier mais chaque module < 600 LOC | Éviter monstres style yabai 30 KLOC |
| B. Zéro dépendance externe | **Assoupli** : TOMLKit accepté pour parsing config | Justification : parser TOML maison = 200 LOC supplémentaires inutiles. Réversible en V2 |
| C. Identifiants stables uniquement | PASS | CGWindowID partout |
| D. Fail loud, no fallback | PASS | Daemon log explicite, jamais retry silencieux |
| E. Format texte plat | PASS | TOML pour config (lisible vi), JSON-lines pour logs/socket protocol |
| F. CLI minimaliste | Adapté : ~10 commandes au lieu de 4 | Justifié par la richesse fonctionnelle (focus/move/resize/tiler/stage) |

**Action requise** : nouvelle constitution projet à écrire pour SPEC-002 dans `.specify/memory/constitution-002.md` capturant ces ajustements (à faire en Phase Implementation T001).

### Vérification cumulée

- [x] Aucune nouvelle dépendance non justifiée (TOMLKit justifié, à éliminer en V2)
- [x] Aucun usage SkyLight ou scripting addition (FR-005)
- [x] CGWindowID utilisé partout
- [x] Click-to-focus traité comme objectif différenciateur explicite

**Verdict** : aucune violation bloquante. Décisions architecturales et trade-offs documentés.

## Project Structure

### Documentation

```text
specs/002-tiler-stage/
├── plan.md                              # Ce fichier
├── research.md                          # ✓ produit (820 lignes, étude yabai+AeroSpace)
├── data-model.md                        # à produire en Phase 1
├── contracts/
│   ├── cli-protocol.md                  # contrat CLI ↔ daemon
│   └── tiler-protocol.md                # contrat protocole Tiler Swift
├── quickstart.md                        # à produire
├── checklists/
│   └── requirements.md                  # ✓ validation spec (13/13 PASS)
├── tasks.md                             # produit par /speckit.tasks
└── implementation.md                    # journal + REX
```

### Source Code

```text
Package.swift                            # SPM manifest, 4 targets
Sources/
├── RoadieCore/                          # 13 fichiers, ~870 LOC effectives
│   ├── AXEventLoop.swift                # Thread/app, AXObserver, CFRunLoop, kAXMainWindowChanged + per-window destroy subscription
│   ├── GlobalObserver.swift             # NSWorkspace activations + termination
│   ├── WindowRegistry.swift             # [WindowID: WindowState] + MRU stack focus (insertionTarget)
│   ├── FocusManager.swift               # État focus + sync via kAXApplicationActivatedNotification (différenciateur)
│   ├── DisplayManager.swift             # NSScreen + workspace mapping
│   ├── Server.swift                     # NWListener socket Unix
│   ├── Config.swift                     # TOML parsing (TOMLKit)
│   ├── Logger.swift                     # JSON-lines log writer + rotation 10 MB
│   ├── Types.swift                      # WindowState, Direction, Orientation, TilerStrategy (struct String-based)
│   ├── PrivateAPI.swift                 # @_silgen_name _AXUIElementGetWindow
│   ├── Protocol.swift                   # Request/Response/AnyCodable (CLI ↔ daemon)
│   ├── MouseRaiser.swift                # T084 — click-to-raise via NSEvent global monitor
│   └── PeriodicScanner.swift            # T085 — filet 1 sec pour Electron silencieux
├── RoadieTiler/                         # 6 fichiers, ~500 LOC
│   ├── TilerProtocol.swift              # protocol Tiler
│   ├── TreeNode.swift                   # noeud N-aire avec adaptiveWeight + lastFrame (auto-orientation)
│   ├── BSPTiler.swift                   # impl BSP avec auto-orientation par aspect ratio
│   ├── MasterStackTiler.swift           # impl Master-Stack
│   ├── TilerRegistry.swift              # T082 — registre dynamique des stratégies (architecture pluggable)
│   └── LayoutEngine.swift               # calcul récursif + apply via AX + setStrategy throws si inconnue
├── RoadieStagePlugin/
│   ├── StageManager.swift               # logique principale
│   ├── WindowGroup.swift                # groupe = liste WindowID + tiler choisi
│   ├── HideStrategy.swift               # off-screen vs minimize
│   └── StageObserver.swift              # subscribe core events
├── roadied/                             # binaire daemon
│   └── main.swift                       # bootstrap + server loop
└── roadie/                              # binaire CLI
    ├── main.swift                       # parse args + socket client
    ├── SocketClient.swift               # NWConnection
    └── OutputFormatter.swift            # text + json output
Tests/
├── RoadieCoreTests/
│   └── ConfigParserTests.swift
├── RoadieTilerTests/
│   ├── TreeNodeTests.swift
│   ├── BSPTilerTests.swift
│   └── MasterStackTilerTests.swift
└── integration/
    ├── 01-daemon-startup.sh
    ├── 02-cli-roundtrip.sh
    └── 03-config-reload.sh
docs/
├── decisions/
│   ├── ADR-001-ax-per-app-no-skylight.md
│   ├── ADR-002-tree-naire-vs-bsp-binary.md
│   └── ADR-003-hide-corner-vs-minimize.md
└── manual-acceptance/
    ├── tiling-bsp.md
    ├── click-to-focus.md
    └── stage-switching.md
Makefile
README.md
```

**Structure Decision** : Swift Package Manager classique avec séparation claire en 4 targets bibliothèques + 2 exécutables. La séparation `RoadieCore`/`RoadieTiler`/`RoadieStagePlugin` rend la modularité explicite — `RoadieStagePlugin` peut être désactivé via flag de build sans impacter Core+Tiler. Pas de mono-fichier (incompatible avec ce scope) mais chaque fichier < 200 LOC pour rester lisible.

## Phase 0 — Research (déjà complété)

`research.md` produit (820 lignes, ~6 000 mots) couvre :

1. Pattern event loop AX (yabai vs AeroSpace) — décision : AeroSpace style
2. Modèle arbre tiling — décision : N-aire avec adaptiveWeight
3. Stratégie masquage workspace — décision : coin écran + minimize fallback
4. Click-to-focus — décision : `kAXApplicationActivatedNotification` (innovation vs AeroSpace)
5. API privées — uniquement `_AXUIElementGetWindow`, zéro SkyLight
6. Multi-monitor — reporté V2
7. Configuration & CLI — TOML + socket Unix
8. Synthèse architecturale — 4 modules, 2 240 LOC estimés
9. Pièges identifiés — race conditions au démarrage, popups/dialogs, apps Zoom/Teams
10. Plan de lecture sources

## Phase 1 — Design (à exécuter)

### data-model.md (à produire)

Définit les structures Swift clés :

- `WindowState` (struct) — state canonique par fenêtre
- `TreeNode` (class) — noeud N-aire avec children[], adaptiveWeight, parent (weak)
- `TilingContainer` (subclass TreeNode) — orientation + layout
- `WindowLeaf` (subclass TreeNode) — feuille avec windowID
- `Workspace` (struct) — racine arbre + tilerStrategy
- `Stage` (struct) — nom + Set<WindowID> + tilerStrategy
- `Direction` (enum) — left/right/up/down
- `Command` (enum) — typé pour tout ce qui passe sur le socket
- `Response` (enum) — réponse daemon, success/error
- Validation rules par champ
- État transitions (window created → registered → tiled → resized → destroyed)

### contracts/cli-protocol.md (à produire)

Format messages CLI ↔ daemon :
- Encoding JSON-lines sur le socket Unix
- Schema de chaque commande supportée
- Codes d'erreur standardisés
- Versioning du protocole (header `roadie/1`)
- Exemples d'échanges

### contracts/tiler-protocol.md (à produire)

Le protocole Swift `Tiler` complet :
- Méthodes obligatoires
- Méthodes optionnelles avec défaults
- Invariants (idempotence du layout, pure function)
- Comment ajouter une nouvelle stratégie (process pour V2+)

### quickstart.md (à produire)

Install + premier run en 10 minutes :
- Build via `swift build -c release`
- Install : copier binaires + créer LaunchAgent
- Permission Accessibility (le binaire daemon DOIT être ad-hoc signé pour TCC, comme appris de SPEC-001)
- Premier roadied + premier `roadie windows list`
- Configurer 2 stages
- Câbler hotkeys via Karabiner ou BTT

### Agent context update

`.specify/scripts/bash/update-agent-context.sh claude` à exécuter après data-model + contracts pour générer un `CLAUDE.md` à la racine du worktree avec les conventions du projet.

## Phase 2 — Tasks (à exécuter par `/speckit.tasks`)

Découpage en user stories :

- **US1 BSP tiling** : 8-12 tâches (TreeNode + BSP + LayoutEngine + tests)
- **US2 Click-to-focus** : 6-10 tâches (FocusManager + GlobalObserver + tests intégration)
- **US3 Stage plugin** : 8-12 tâches (StageManager + HideStrategy + tests bascule)
- **US4 Master-Stack** : 4-6 tâches (impl alternative + test mode change)

Plus phases Setup/Foundational/Polish habituelles. Total estimé : 60-80 tâches.

## Phase 3+ — Implementation

Suivre tasks.md phase par phase. Itérations courtes, tests à chaque user story complète.

## Complexity Tracking

Trois écarts par rapport à SPEC-001 méritent justification :

| Écart | Raison | Alternative rejetée |
|---|---|---|
| Multi-fichier (vs mono-fichier SPEC-001) | Scope ~2 500 LOC ingérable en mono-fichier (lisibilité, recompilation) | Mono-fichier 2 500 LOC = ingérable |
| Dépendance TOMLKit | Parser TOML maison = ~200 LOC + bugs probables sur edge cases (multi-line strings, dates, arrays of tables) | Parser maison reporté en V2 si vraiment nécessaire |
| Daemon long-running (vs CLI one-shot SPEC-001) | Imposé par la nécessité d'observer les events AX en temps réel — un CLI one-shot ne peut pas réagir aux nouvelles fenêtres | Polling 100 ms = consommation batterie inacceptable |

Ces 3 écarts sont structurels au type de projet. Pas de violation constitution si la nouvelle constitution projet (à écrire en T001) les valide explicitement.
