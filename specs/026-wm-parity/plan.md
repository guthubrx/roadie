# Implementation Plan: WM-Parity Hyprland/Yabai (Lot Consolidé)

**Branch**: `026-wm-parity` | **Date**: 2026-05-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/026-wm-parity/spec.md`

## Summary

Lot consolidé de 9 features SIP-on inspirées de Hyprland et yabai : commandes tree (balance/rotate/mirror), smart_gaps_solo, scratchpad, sticky cross-stage, follow focus bidirectionnel, signal hooks. Toutes opt-in via TOML (3 toggles obligatoires + 3 sections par déclaration). Approche : extension minimale des composants existants (`BSPTiler`, `LayoutEngine`, `FocusManager`, `WindowRegistry`, `EventBus`, `PinEngine`) sans refactor surrounding. Tests unitaires sur logique pure obligatoires.

## Technical Context

**Language/Version**: Swift 5.9+, macOS 14+
**Primary Dependencies**: Cocoa, ApplicationServices, CoreGraphics, IOKit (système macOS uniquement, principe B' constitution)
**Storage**: Fichiers TOML (`~/.config/roadies/roadies.toml`) + état stage existant (`~/.roadies/stages/`). Pas de nouveau stockage persistant pour cette spec.
**Testing**: XCTest (déjà en place dans `Tests/`)
**Target Platform**: macOS 14+ (Apple Silicon + Intel), SIP-on strict
**Project Type**: Daemon multi-modules (Swift Package Manager interne — autorisé pour ce projet, dérogation principe B documentée dans constitution-002)
**Performance Goals**:
  - p95 `applyAll` ≤ 250ms (SC-004) avec toutes les features actives.
  - focus_follows_mouse throttle 100ms.
  - signal cmd timeout strict 5s.
**Constraints**:
  - SIP-on strict (aucune dépendance scripting addition).
  - Aucune dépendance tierce nouvelle (Swift system frameworks uniquement).
  - Aucun feedback loop entre focus_follows_mouse et mouse_follows_focus.
**Scale/Scope**:
  - 9 features livrées en 1 spec.
  - **Cible LOC effectives : 700**
  - **Plafond LOC effectives strict : 900**
  - Mesure : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l` (delta avant/après merge).

## Constitution Check

| Gate | Status | Justification |
|---|---|---|
| A. Suckless avant tout | ✅ PASS | chaque feature isolée < 200 LOC ; tree commands < 100 LOC chacune ; smart_gaps < 30 LOC ; scratchpad/sticky/follow/signals tirent parti des structures existantes |
| B'. Zéro dépendance externe | ✅ PASS | aucune nouvelle dépendance, tout via frameworks système |
| C. Identifiants stables uniquement | ✅ PASS | scratchpad attache la wid via `CGWindowID` matché sur bundleID+frame, pas (bundleID, title) |
| D. Fail loud, no fallback | ✅ PASS | scratchpad timeout → log warn explicite ; signal timeout → SIGTERM/SIGKILL + log ; commandes tree no-op explicite si tree vide |
| E. État sur disque format texte | ✅ PASS | aucun nouveau fichier d'état ; tout dans roadies.toml + state stages existant |
| F. CLI minimaliste | ⚠️ EXTENSION | ajout de `tiling balance/rotate/mirror` et `scratchpad toggle` — extensions cohérentes du verbe `tiling` existant et nouveau verbe `scratchpad`. Reste minimaliste (verbes single-action). |
| G. Plafond LOC déclaré | ✅ PASS | cible 700, plafond 900 déclarés ci-dessus |

**Toutes les gates passent ou sont justifiées.** Aucun blocage Constitution Check.

## Project Structure

### Documentation (this feature)

```text
specs/026-wm-parity/
├── plan.md              # This file
├── spec.md              # Feature spec
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cli-commands.md  # Nouvelles commandes CLI roadie
│   └── toml-schema.md   # Nouvelles clés TOML
├── checklists/
│   └── requirements.md  # Validation spec
└── tasks.md             # Phase 2 output (généré par /speckit.tasks)
```

### Source Code (repository root)

Extension des composants existants — **aucun nouveau target SwiftPM**.

```text
Sources/
├── RoadieCore/
│   ├── Config.swift                # +clés [focus] focus_follows_mouse, mouse_follows_focus ; [tiling] smart_gaps_solo ; [signals] enabled ; [[scratchpads]] ; [[signals]]
│   ├── FocusManager.swift          # +mouse_follows_focus warp + flag anti-feedback 200ms
│   ├── MouseDragHandler.swift      # déjà touché en SPEC précédente, lecture isDragging seule
│   └── WindowRegistry.swift        # extension scope : sticky_scope dans WindowState (champ optionnel)
├── RoadieTiler/
│   ├── BSPTiler.swift              # +balance/rotate/mirror operations + smart_gaps_solo dans applyAll
│   ├── MasterStackTiler.swift      # +balance (uniforme), rotate (swap orientations), mirror (no-op ou swap master/stack)
│   └── LayoutEngine.swift          # exposition commandes via TilerProtocol, smart_gaps detection per-display
├── RoadieStagePlugin/
│   └── StageManager.swift          # +sticky_scope honoré dans memberWindows projection (cross-stage matching)
├── roadied/
│   ├── CommandRouter.swift         # +cases tiling.balance/rotate/mirror, scratchpad.toggle, daemon.reload-aware
│   ├── ScratchpadManager.swift     # NEW (~80 LOC) : déclaration, toggle, attachement wid
│   ├── SignalDispatcher.swift      # NEW (~120 LOC) : EventBus subscription + Process spawn + timeout
│   └── FocusFollowsMouseWatcher.swift  # NEW (~80 LOC) : NSEvent monitor + throttle
├── roadie/
│   └── main.swift                  # +sous-verbes `tiling balance|rotate|mirror`, `scratchpad toggle <name>`
└── (Tests existants étendus)

Tests/
├── RoadieTilerTests/
│   ├── TreeOpsTests.swift          # NEW : balance/rotate/mirror logique pure
│   └── SmartGapsTests.swift        # NEW : detection count==1
├── RoadieCoreTests/
│   └── ConfigTests.swift           # +tests décodage nouvelles clés TOML
└── roadiedTests/
    ├── ScratchpadTests.swift       # NEW : toggle round-trip
    ├── SignalDispatcherTests.swift # NEW : env injection + timeout
    └── FollowFocusTests.swift      # NEW : anti-feedback loop
```

## Phase 0 — Research Technique

Voir `research.md` pour le détail. Synthèse :

| Question | Décision | Source |
|---|---|---|
| Comment monitorer `mouseMoved` global sans race avec drag ? | `NSEvent.addGlobalMonitorForEvents` + check `MouseDragHandler.isDragging` avant action | pattern déjà utilisé dans `MouseDragHandler` |
| Comment warper le curseur sans interrompre le focus AX ? | `CGWarpMouseCursorPosition` (CoreGraphics) — async, pas d'event synthétique | Apple CGRemoteOperations.h |
| Comment lancer un process shell async fire-and-forget avec timeout ? | `Process` + `Task` async + `DispatchQueue.global().asyncAfter(deadline:)` pour kill timer | Foundation standard |
| Comment matcher la fenêtre produite par le `cmd` du scratchpad ? | Watch `EventBus.window_created` pendant 5s post-spawn, prendre la 1ère wid avec `bundleID` matchant le binaire de cmd (heuristic) ; fallback : prendre la 1ère wid de l'app frontmost dans la fenêtre temporelle | inspiré yabai `--criteria` |
| Comment éviter un feedback loop focus_follows_mouse ↔ mouse_follows_focus ? | flag `inhibitFollowMouse` Date+200ms posé par mouse_follows_focus, vérifié par focus_follows_mouse au début de son handler | invention propre, validée par scénario test |
| Sticky scope=all sans clonage cross-display ? | déplacer la wid vers le display courant à chaque `display_changed` (CGS displayID change) | yabai sticky comportement, doc officiel |

## Phase 1 — Design & Contracts

### Data Model

Voir `data-model.md`. Entités principales :

- **ScratchpadDef** (Codable, dans Config) : `name: String`, `cmd: String`, `match: ScratchpadMatch?` (optional override pour le bundleID matché).
- **ScratchpadState** (runtime, in-memory) : `name: String`, `wid: WindowID?`, `isVisible: Bool`, `lastVisibleFrame: CGRect?`.
- **StickyScope** (enum) : `.stage`, `.desktop`, `.all`. Champ ajouté à `RuleDef` existant.
- **SignalDef** (Codable) : `event: String`, `cmd: String`. Validation event ∈ liste fermée.
- **FocusConfig** (extension de la struct existante) : ajout de `focusFollowsMouse: Bool`, `mouseFollowsFocus: Bool`.
- **TilingConfig** (extension) : ajout de `smartGapsSolo: Bool`.
- **SignalsConfig** (nouvelle section) : `enabled: Bool` + `signals: [SignalDef]`.
- **TreeOp** (interface ajoutée à TilerProtocol) : `balance(in scope)`, `rotate(angle, in scope)`, `mirror(axis, in scope)`. Pas une struct, juste 3 méthodes pures.

### CLI Contracts

Voir `contracts/cli-commands.md`. Nouvelles commandes :

```
roadie tiling balance
roadie tiling rotate <90|180|270>
roadie tiling mirror <x|y>
roadie scratchpad toggle <name>
```

Aucune commande `enable/disable` pour les follow-focus et smart_gaps : toggles uniquement via TOML + `roadie daemon reload`.

### TOML Schema

Voir `contracts/toml-schema.md`. Nouvelles clés :

```toml
[tiling]
smart_gaps_solo = false   # NEW

[focus]
focus_follows_mouse = false   # NEW
mouse_follows_focus = false   # NEW

[signals]
enabled = true   # NEW

[[signals]]   # NEW, répétable
event = "window_focused"
cmd = "afplay /System/Library/Sounds/Tink.aiff"

[[scratchpads]]   # NEW, répétable
name = "term"
cmd = "open -na 'iTerm'"

[[rules]]   # EXTENSION du existant
match.bundle_id = "com.tinyspeck.slackmacgap"
sticky_scope = "stage"   # NEW (default "stage" si absent dans une rule sticky)
```

### Quickstart

Voir `quickstart.md`. Steps utilisateur :

1. Backup `~/.config/roadies/roadies.toml`.
2. Ajouter les sections désirées (au moins une, sinon tout reste inerte).
3. `roadie daemon reload`.
4. Tester chaque feature activée selon scénarios de la spec.
5. Si problème, désactiver via toggle TOML et reload.

### Agent context update

Le projet n'utilise pas d'agent IA externe avec contexte (pas de Cursor/Copilot config dans le repo). Skip cette étape.

## Phase 2 — Stop point

Le `plan.md` est complet. La phase suivante est `tasks.md` générée par `/speckit.tasks`.

## Complexity Tracking

Aucune dérogation à la constitution. Toutes les gates passent (1 extension justifiée du principe F, gate G respectée avec plafond 900).

**Anticipation risque LOC** : le plafond strict 900 ne tolère que ~30% de marge sur la cible 700. Si une feature dérape (>200 LOC), elle DOIT être refactor avant merge. Audit obligatoire en Phase 6.

## Justifications Architecture

- **Pourquoi un seul `ScratchpadManager` plutôt qu'une intégration dans `StageManager`** : isolation du cycle de vie scratchpad (spawn/visibility) qui est asynchrone et indépendant des stages.
- **Pourquoi `SignalDispatcher` séparé du `EventBus`** : EventBus est synchrone in-process ; les signaux sont des side-effects async fire-and-forget vers le shell. Single-responsibility.
- **Pourquoi `FocusFollowsMouseWatcher` séparé de `MouseRaiser`** : MouseRaiser observe les `mouseDown` (raise on click), FocusFollowsMouseWatcher observe `mouseMoved` (focus on hover).
- **Pourquoi étendre `RuleDef` existant pour sticky_scope plutôt qu'une nouvelle entité** : SPEC-016 a déjà un `RuleDef` ; sticky_scope est un champ supplémentaire.

## Re-evaluation Constitution Check (post-design)

Toutes les gates restent respectées après design détaillé. Pas de surprise architecturale.
