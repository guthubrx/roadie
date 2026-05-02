# Implementation Plan: Roadie Multi-Display

**Branch**: `012-multi-display` | **Date**: 2026-05-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/012-multi-display/spec.md`

## Summary

Extension de SPEC-011 pour la gestion native du multi-écran. Architecture cible :

- **`DisplayRegistry`** (nouveau, `RoadieCore`) : actor qui maintient la liste des écrans physiques connectés (énumérés via `NSScreen.screens`), leur identifiant Quartz stable (`CGDirectDisplayID`), leur `frame`/`visibleFrame`, et un mapping cgwid → écran d'origine. Observe `NSApplication.didChangeScreenParametersNotification` pour réagir aux changements (branch/débranch/repositionnement).

- **`LayoutEngine`** (modifié, `RoadieTiler`) : devient multi-rect. À la place de l'unique `apply(rect:)`, `applyAll()` itère sur tous les écrans et applique le layout de chacun dans son `visibleFrame` propre. Chaque écran a son propre `TilingContainer` racine.

- **`Display`** (nouvelle entité) : id (CGDirectDisplayID), index (1-based), uuid (string stable), name (depuis NSScreen), frame, visibleFrame, isMain, isActive, tilerStrategy, gapsOuter, gapsInner.

- **CLI étendue** (`Sources/roadie/main.swift`) : `roadie display list/current/focus`, `roadie window display N`. Handlers correspondants dans `Sources/roadied/CommandRouter.swift`.

- **Persistance étendue** (`RoadieDesktops.WindowEntry`) : ajout du champ `displayUUID: String?` pour mémoriser l'écran d'origine. Backward-compatible (champ optionnel, vide pour les anciennes entrées).

- **Recovery branch/débranch** : à `didChangeScreenParameters`, calcul de la diff (écrans ajoutés/retirés). Pour chaque écran retiré, migration des fenêtres vers le primary screen avec frame ajustée.

- **Events** : nouveaux types `display_changed` (focus passe d'un écran à l'autre) et `display_configuration_changed` (liste écrans modifiée).

Multi-display est orthogonal à SPEC-011 : un desktop courant reste global, mais ses fenêtres sont distribuées sur tous les écrans connectés selon leur position d'origine. La bascule de desktop continue de masquer toutes les fenêtres (tous écrans confondus) et restaure celles du desktop d'arrivée à leur expectedFrame stockée (qui contient des coordonnées globales, donc le bon écran).

## Technical Context

**Language/Version** : Swift 5.9, ciblant Swift 6 mode strict (état actuel du projet).
**Primary Dependencies** : `NSScreen` (AppKit, déjà importé partout pour SPEC-011 hide multi-display), `NotificationCenter` pour `didChangeScreenParametersNotification`, `CGDisplayCreateUUIDFromDisplayID` (CoreGraphics public, pour récupérer un UUID stable). Aucune nouvelle dépendance tierce.
**Storage** : extension du `state.toml` per-desktop existant, ajout du champ `display_uuid` optionnel sur `[[windows]]`. Backward-compatible.
**Testing** : `swift test` via SwiftPM. Tests unitaires sur `DisplayRegistry`, `LayoutEngine` multi-rect, recovery branch/débranch via mock d'écrans. Tests d'intégration optionnels via mock `NSScreen.screens`.
**Target Platform** : macOS 14+ (Sonoma), prioritaire macOS 26 Tahoe.
**Project Type** : single project Swift, multi-modules SwiftPM.
**Performance Goals** : `roadie window display N` < 200 ms p95 (FR-008, SC-002). Migration recovery déconnexion < 500 ms (FR-015, SC-003). `applyAll()` scale linéairement avec le nombre d'écrans (négligeable jusqu'à 8 écrans).
**Constraints** :
- Aucun appel SkyLight/CGS pour le multi-display (FR-007, SC-007). Vérifié par grep statique sur `Sources/RoadieCore/DisplayRegistry.swift` (futur fichier).
- 0 régression mono-écran (FR-024, SC-004) : la suite SPEC-011 doit passer sans modification.
- Thread-safety : observers AX et NSNotifications arrivent sur threads distincts, isolation par actor.
**Scale/Scope** : 1..N écrans (cible ≤ 8). Tests prioritaires sur 1, 2, 3 écrans.

### Cible et plafond LOC (principe G constitution)

- **Cible LOC effectives** : 600 LOC (Swift, hors commentaires/blanches)
- **Plafond strict** : 800 LOC (+33 %)

Composants attendus :

| Composant | LOC cible |
|---|---|
| `RoadieCore/DisplayRegistry.swift` (nouveau) | ~250 |
| `RoadieCore/Display.swift` (entité) | ~80 |
| `RoadieTiler/LayoutEngine.swift` (modifs `applyAll`) | ~50 (delta) |
| `RoadieDesktops/DesktopState.swift` (champ displayUUID) | ~10 (delta) |
| `RoadieDesktops/Migration.swift` (compat) | ~20 (delta) |
| `roadied/CommandRouter.swift` (handlers display.*) | ~80 |
| `roadie/main.swift` (sous-commandes display/window display) | ~40 |
| `Tests/RoadieCoreTests/DisplayRegistryTests.swift` | ~120 |
| `Tests/RoadieDesktopsTests/MultiDisplayPersistenceTests.swift` | ~50 |
| **Total cible** | **~600 (+~50 dans modules existants)** |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Aucun `import Package` ni dépendance tierce nouvelle** : seulement AppKit (NSScreen) + CoreGraphics (CGDisplayCreateUUIDFromDisplayID), déjà liés.
- [x] **Aucun usage de `(bundleID, title)` comme clé primaire** : les écrans sont identifiés par `CGDirectDisplayID` (UInt32), les fenêtres restent identifiées par `CGWindowID`.
- [x] **Toute action sur fenêtre tracée à un `CGWindowID`** : `roadie window display N` opère sur `daemon.registry.focusedWindowID`.
- [x] **Binaire `roadied` < 5 MB** : extension marginale (+~50 KB estimés).
- [x] **Cible et plafond LOC déclarés** : 600 / 800.

**Principes A-G** :

- **A. Suckless** : aucune fonction ne dépasse 50 LOC à elle seule. La plus grosse, `DisplayRegistry.handleScreenChange()`, ~40 LOC.
- **B. Zéro dépendance externe** : 0 dépendance ajoutée.
- **C. Identifiants stables** : `CGDirectDisplayID` (Quartz) pour les écrans (stable cross-reboot pour le même hardware), `CGWindowID` pour les fenêtres.
- **D. Fail loud** : si écran absent au boot pour un `display_uuid` persisté, log warning + fallback primary (FR-017). Pas de retry silencieux.
- **E. État sur disque format texte plat** : extension TOML existante, champ optionnel.
- **F. CLI minimaliste** : 4 sous-commandes display (list, current, focus, ensemble window display) — légère extension acceptée par cohérence avec yabai/AeroSpace, alignée avec la justification SPEC-011.
- **G. LOC** : déclaré ci-dessus.

**Verdict** : toutes les gates passent. Pas de Complexity Tracking nécessaire.

## Project Structure

### Documentation (this feature)

```text
specs/012-multi-display/
├── plan.md              # This file
├── research.md          # Phase 0 — choix techniques
├── data-model.md        # Phase 1 — entités + transitions
├── quickstart.md        # Phase 1 — comment tester
├── contracts/
│   ├── cli-display.md
│   └── cli-window-display.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 — généré par /speckit.tasks
```

### Source Code (repository root)

```text
Sources/
├── RoadieCore/
│   ├── Display.swift              # NEW — entité Display
│   ├── DisplayRegistry.swift      # NEW — actor + observer didChangeScreenParameters
│   └── (autres fichiers inchangés)
├── RoadieTiler/
│   └── LayoutEngine.swift         # MODIFIÉ — applyAll() multi-rect
├── RoadieDesktops/
│   ├── DesktopState.swift         # MODIFIÉ — WindowEntry.displayUUID optionnel
│   ├── Migration.swift            # MODIFIÉ — compat champs sans displayUUID
│   └── DesktopBackedStagePersistence.swift
├── roadied/
│   ├── CommandRouter.swift        # MODIFIÉ — handlers display.* + window.display
│   └── main.swift                 # MODIFIÉ — init DisplayRegistry au boot
└── roadie/
    └── main.swift                 # MODIFIÉ — sous-commandes display/window display

Tests/
├── RoadieCoreTests/
│   └── DisplayRegistryTests.swift
└── RoadieDesktopsTests/
    └── MultiDisplayPersistenceTests.swift
```

**Structure Decision** : `DisplayRegistry` vit dans `RoadieCore` (primitif, partagé par Tiler et Desktops). Aucun nouveau module SwiftPM nécessaire — modifs = extensions de modules existants. `LayoutEngine` reste dans `RoadieTiler` mais expose désormais `applyAll(displayRegistry:)` qui consomme le DisplayRegistry pour itérer.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Principe F (CLI minimaliste — 4 sous-commandes max) — SPEC-012 ajoute `display list/current/focus` + `window display` (4 nouvelles sous-commandes, sur le verbe `display` et le verbe `window`) | Cohérence avec yabai/AeroSpace : `display` est un verbe distinct de `desktop`/`stage`/`window`, pour gérer les écrans physiques. L'utilisateur power-user multi-écran s'attend à `display list/focus` par convention. La justification déjà acceptée pour SPEC-011 (extension contextuelle par verbe) s'applique : on étend le verbe `display` (4 sous-commandes), pas le verbe `stage` (qui reste à 4) | (a) Fusionner display.* dans desktop.* : confond les concepts (un desktop ≠ un écran). (b) Pas de `display.focus` : régression UX. (c) Pas de `window display N` : pas de mécanisme pour déplacer une fenêtre entre écrans = feature inachevée. La constitution parle de 4 sous-commandes pour le verbe stage ; ici on étend les verbes `display` (nouveau) et `window` (déjà existant) |
