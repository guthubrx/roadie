# Implementation Plan: Multi-desktop awareness (roadies V2)

**Branch** : `003-multi-desktop` | **Date** : 2026-05-01 | **Spec** : [spec.md](./spec.md)
**Input** : Feature specification from `/specs/003-multi-desktop/spec.md`

## Summary

Roadie V2 ajoute la conscience des **desktops macOS** (Spaces Mission Control). Le daemon observe le desktop actif via API SkyLight stable + observer public AppKit, persiste un état séparé par UUID de desktop (stages V1, tree BSP, layout, gaps, assignments fenêtres), et bascule automatiquement le contexte quand l'utilisateur change de desktop natif. Les stages V1 (⌥1 / ⌥2) sont **strictement préservés** — ils restent l'équivalent fonctionnel d'Apple Stage Manager sur **un même desktop**. Le multi-desktop est **opt-in** via config (`multi_desktop.enabled = false` par défaut → comportement V1 strict). Nouvelles commandes CLI `roadie desktop list/focus/current/label/back` et `roadie events --follow` (JSON-lines stream pour intégrations menu bar). Multi-display reporté en V3.

## Technical Context

**Language/Version** : Swift 5.9+ (toolchain Xcode), `@MainActor` Swift Concurrency (continuation V1)

**Primary Dependencies** :
- Frameworks système : `Cocoa`, `ApplicationServices`, `CoreGraphics`, `Network`, `IOKit.hid`, `Carbon` (continuation V1)
- Framework privé linké : `/System/Library/PrivateFrameworks/SkyLight.framework` (déjà linké en V1) — réutilisé en V2 pour `CGSGetActiveSpace`, `CGSCopyManagedDisplaySpaces`
- Notification publique : `NSWorkspace.activeSpaceDidChangeNotification` (AppKit, pas privée) — événement principal pour observer les transitions
- API privées stables (déclarées via `@_silgen_name`) : `CGSMainConnectionID`, `CGSGetActiveSpace`, `CGSCopyManagedDisplaySpaces` — toutes lecture seule, sans SIP off requis
- Réutilise V1 : TOMLKit pour parsing config, persistance fichier atomique

**Storage** :
- Config : `~/.config/roadies/roadies.toml` (extension de la V1 avec sections `[multi_desktop]` + `[[desktops]]`)
- État par desktop : `~/.config/roadies/desktops/<uuid>.toml` (nouveau)
- Migration V1→V2 : à premier boot V2, déplacement automatique de `~/.config/roadies/stages/*.toml` (V1) vers `~/.config/roadies/desktops/<current-desktop-uuid>.toml`
- Socket : `~/.roadies/daemon.sock` (continuation)
- Logs : `~/.local/state/roadies/daemon.log` (continuation)

**Testing** :
- Tests unitaires XCTest pour `DesktopManager` (mock SkyLight via protocol injection), `DesktopState` round-trip TOML, migration V1→V2
- Tests d'intégration shell qui scriptent Mission Control via `osascript` pour basculer entre desktops
- Tests d'acceptation manuels documentés (10 scénarios couvrant les 4 user stories + edge cases)

**Target Platform** : macOS 14 (Sonoma) min, prioritaire 15 (Sequoia) et 26 (Tahoe). Universal x86_64 + arm64.

**Project Type** : Single project — Swift Package Manager. Continuation des 5 targets V1 (RoadieCore, RoadieTiler, RoadieStagePlugin, roadied, roadie). Nouveau module `Sources/RoadieCore/DesktopManager.swift`. Extension de `RoadieStagePlugin/StageManager.swift` pour l'indexation par desktop.

**Performance Goals** :
- Switch contexte au desktop_changed < 200 ms (SC-001)
- 100 % restauration fidèle sur 100 cycles (SC-002)
- Soutien 10 desktops × 10 stages sans dégradation (SC-003)
- Events stream sans perte sur 1000 transitions (SC-004)

**Constraints** :
- LOC ajoutées V2 ≤ 800 effectives (SC-008) ; cumulé V1+V2 ≤ 4 000 LOC strict (constitution G + G')
- Pas de SIP désactivé (FR-005 SPEC-002, applicable ici aussi)
- Compat ascendante stricte (SC-005) : utilisateur V1 ne voit aucune régression sans toucher sa config
- Aucune dépendance runtime nouvelle (SC-006)
- Fichiers d'état desktop ≤ 50 KB (SC-007)

**Scale/Scope** :
- 1 utilisateur, 1 machine, 1 display (V2)
- Jusqu'à 20 desktops macOS, 10 stages par desktop, 50 fenêtres tilées par desktop
- Multi-display reporté V3

## Constitution Check

*GATE : doit passer avant Phase 0 research. Re-vérifié après Phase 1 design.*

### Constitution Globale (`@~/.speckit/constitution.md`)

| Principe | Conformité |
|---|---|
| **A — Préservation Loi de Conservation** | ✅ aucune intention V1 supprimée, multi-desktop est additif |
| **B — Documentation continue** | ✅ spec/plan/tasks/research/data-model produits |
| **C — Tests automatisés** | ✅ XCTest unitaires + intégration shell prévus |
| **D — Sessions traçables (SpecKit)** | ✅ branche `003-multi-desktop`, worktree dédié |
| **G — Mode Minimalisme LOC** | ✅ plafond 800 LOC ajoutées (sur 4000 strict cumulé), 35 % marge V1+V2 |

### Constitution Projet (`.specify/memory/constitution.md`)

| Principe | Conformité |
|---|---|
| **F — API privées stables sans SIP off** | ✅ uniquement `CGSGetActiveSpace` + observer public NSWorkspace (lecture seule), pattern yabai/AeroSpace |
| **G' — Plafond 4 000 LOC** | ✅ ~ 2 600 V1 + ≤ 800 V2 = ~ 3 400, sous le plafond |
| **I' — Architecture pluggable** | ✅ DesktopManager indépendant, injection via protocol pour tests, pas de couplage dur StageManager↔SkyLight |

### Vérification cumulée

✅ Toutes les gates passent. **Aucune justification de violation requise.**

## Project Structure

### Documentation (this feature)

```text
specs/003-multi-desktop/
├── plan.md              # ce fichier
├── research.md          # Phase 0 — décisions techniques (SkyLight, persistance, observer pattern)
├── data-model.md        # Phase 1 — entités Desktop, DesktopState, Event, WindowRule
├── quickstart.md        # Phase 1 — install V2 + premier run multi-desktop
├── contracts/
│   ├── cli-protocol.md  # Phase 1 — nouvelles commandes desktop & events
│   └── events-stream.md # Phase 1 — format JSON-lines events
├── checklists/
│   └── requirements.md  # créé par /speckit.specify
└── tasks.md             # Phase 2 (généré par /speckit.tasks)
```

### Source Code (repository root)

Continuation de la structure V1, avec ajouts ciblés :

```text
Sources/
├── RoadieCore/
│   ├── DesktopManager.swift    # NEW — observer + transitions
│   ├── DesktopState.swift      # NEW — modèle persistance par desktop
│   ├── EventBus.swift          # NEW — pub/sub interne pour events
│   ├── Config.swift            # EXT — section [multi_desktop] + [[desktops]]
│   ├── WindowRegistry.swift    # EXT — desktopUUID dans WindowState
│   ├── PrivateAPI.swift        # EXT — bindings SkyLight (CGSGetActiveSpace)
│   └── (V1 inchangés)
├── RoadieStagePlugin/
│   └── StageManager.swift      # EXT — état indexé par desktopUUID, swap au switch
├── RoadieTiler/
│   └── (V1 inchangé — un LayoutEngine par desktop instancié à la demande)
├── roadied/
│   ├── main.swift              # EXT — câblage DesktopManager observer
│   └── CommandRouter.swift     # EXT — handlers desktop.* + events.subscribe
└── roadie/
    └── main.swift              # EXT — verbe `desktop` + `events`

Tests/
├── RoadieCoreTests/
│   ├── DesktopManagerTests.swift   # NEW — mock SkyLight via protocol
│   └── DesktopStateTests.swift     # NEW — TOML round-trip + migration V1→V2
└── integration/
    ├── 06-multi-desktop-switch.sh  # NEW — scripted Mission Control
    └── 07-multi-desktop-migration.sh # NEW — V1 stages → V2 desktops
```

## Phase 0 — Research

Voir [research.md](./research.md) pour le détail.

Synthèse :
- **Observer principal** : `NSWorkspace.activeSpaceDidChangeNotification` (AppKit public). Aucun polling.
- **Récupération UUID** : `CGSCopyManagedDisplaySpaces(cid)` retourne CFArray par display contenant les Spaces avec leur UUID stable. `CGSGetActiveSpace(cid)` donne le `CGSSpaceID` (int) actif → cross-référence avec le tableau pour l'UUID.
- **Pattern persistance** : 1 fichier TOML par UUID de desktop, écriture atomique (temp+rename), lecture lazy au switch in.
- **Migration V1→V2** : déplacement automatique au premier boot V2, basé sur la présence de `~/.config/roadies/stages/` legacy.
- **Window pinning** (FR-024) : faisable via AX en best-effort très limité ; trop fragile pour V2, **DEFER en V3**.

## Phase 1 — Design

### Data Model

Voir [data-model.md](./data-model.md). Entités principales :
- `Desktop` (uuid, index, label?, lastActiveAt)
- `DesktopState` (desktopUUID, stages, currentStageID, rootNode, tilerStrategy, gapsOverride?)
- `Event` (eventName, ts, payload)
- `WindowState` (extension : `desktopUUID` ajouté)

### Contracts

Voir `contracts/cli-protocol.md` pour les commandes :
- `roadie desktop list | focus | current | label | back`
- `roadie events --follow [--filter <event>]`

Voir `contracts/events-stream.md` pour le schéma JSON des événements émis sur le canal events.

### Quickstart

Voir [quickstart.md](./quickstart.md) — install V2, activation `multi_desktop.enabled = true`, validation premier switch.

### Agent context update

Pas applicable ici (pas d'agent IA en runtime côté roadie).

## Re-évaluation Constitution Check (post Phase 1 design)

Les 3 nouveaux modules (DesktopManager, DesktopState, EventBus) + extensions Config/WindowRegistry/StageManager restent dans le périmètre LOC ≤ 800. Pas de couplage dur introduit (DesktopManager injecte un observer via protocol, EventBus est un pub/sub minimal). Pas de nouvelle dépendance runtime.

✅ Gates restent passantes. Pipeline débloqué pour Phase 3 Tasks.

## Complexity Tracking

Pas de violations à justifier. Le multi-desktop ajoute une dimension orthogonale sans complexifier les flows V1 existants. La conditionnalité `multi_desktop.enabled` permet de désactiver complètement la couche V2 et de retomber sur le comportement V1 — option "kill switch" qui réduit le risque.
