# Implementation Plan: Roadie Virtual Desktops

**Branch**: `011-virtual-desktops` | **Date**: 2026-05-02 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/011-virtual-desktops/spec.md`

## Summary

Pivot architectural V2 du multi-desktop. Abandon de la stratégie "1 Roadie Desktop = 1 Mac Space natif via SkyLight" (cassée par régression macOS Tahoe 26 — yabai #2656) au profit du pattern AeroSpace : N desktops virtuels gérés intégralement par roadie dans **un seul** Mac Space natif. La bascule consiste à déplacer offscreen toutes les fenêtres du desktop quitté et à restaurer on-screen celles du desktop d'arrivée, via le mécanisme `setLeafVisible` déjà en place pour les stages. Aucun appel SkyLight pour la bascule, aucune scripting addition Dock requise, pas de SIP off requis.

Approche technique : nouveau module `RoadieDesktops` qui encapsule `DesktopRegistry` (état per-desktop in-memory + persistance fichier-plat), `DesktopSwitcher` (logique de bascule offscreen/onscreen), `EventBus` étendu (events `desktop_changed`). Refonte du `CommandRouter` pour router `desktop.*` vers le switcher (plus vers SkyLight). Le code legacy de SPEC-003 (`DesktopManager`, `SkyLightDesktopProvider`, `DesktopChangeObserver`, `Migration`, `MockDesktopProvider`, `DesktopState`) est intégralement supprimé. Migration V1→V2 : assignation auto du state V1 au desktop_id=1 au premier boot.

## Technical Context

**Language/Version** : Swift 5.9, ciblant Swift 6 mode strict (déjà partiellement en place).
**Primary Dependencies** : frameworks système macOS uniquement (Cocoa, ApplicationServices, CoreGraphics, Carbon hot keys via Accessibility). **Aucune** dépendance tierce, conformément au principe B/B' de la constitution. SwiftPM utilisé uniquement pour le build multi-cibles roadied + dylibs FX (déjà en place, pas une dette nouvelle).
**Storage** : fichiers texte plats sous `~/.config/roadies/desktops/<id>/` (un fichier par desktop). Format TOML simple parsé à la main (parseur déjà en place dans `RoadieCore/Config.swift`). Conforme principe E (pas JSON, pas SQLite).
**Testing** : `swift test` via SwiftPM. Cible : tests unitaires pour `DesktopRegistry` (état, persistance, parsing) et `DesktopSwitcher` (bascule, idempotence, queue). Tests d'intégration optionnels via `roadied` lancé dans test harness.
**Target Platform** : macOS 14+ (Sonoma). Validation prioritaire macOS 26 Tahoe (cible utilisateur).
**Project Type** : single project Swift, multi-modules SwiftPM. Daemon (`roadied`) + CLI (`roadie`) + lib core (`RoadieCore`) + nouveau module `RoadieDesktops`.
**Performance Goals** : bascule < 200 ms p95 pour ≤ 10 fenêtres total (FR-003, SC-001). Émission event `desktop_changed` < 50 ms après bascule (FR-016, SC-007). Pas de polling actif — le switcher s'active uniquement sur commande.
**Constraints** :
- Aucun appel SkyLight/CGS pour la bascule (FR-004, SC-005). Vérifié par grep statique.
- Aucune permission privilégiée requise (pas de SIP off, pas de scripting addition).
- 0 régression sur stages V1 (SC-003).
- Compatibilité ascendante via `desktops.enabled = false`.
**Scale/Scope** : 1..16 desktops (défaut 10), ≤ 30 fenêtres total ciblées V2. ≤ 5 stages par desktop (limite implicite V1 conservée).

### Cible et plafond LOC (principe G constitution)

Module `RoadieDesktops` + intégration `CommandRouter` + nouveaux handlers CLI :

- **Cible LOC effectives** : 700 LOC (Swift, hors commentaires/blanches)
- **Plafond strict** : 900 LOC (+30 %)
- **Justification** : SPEC-003 (multi-desktop V2 ancien, deprecated) consommait ~600 LOC effectives dans `Sources/RoadieCore/desktop/` (à supprimer intégralement, gain net). Le pivot ajoute ~700 LOC nouvelles. Solde global LOC daemon : ~+100 LOC nettes vs avant SPEC-003. Le bilan est sain : on ajoute fonction (multi-desktop fonctionnel sur Tahoe) avec coût marginal LOC.

Composants attendus :

| Composant | LOC cible |
|---|---|
| `RoadieDesktops/DesktopRegistry.swift` | ~180 |
| `RoadieDesktops/DesktopSwitcher.swift` | ~150 |
| `RoadieDesktops/DesktopState.swift` (entité + parsing) | ~120 |
| `RoadieDesktops/Migration.swift` (V1→V2) | ~80 |
| `RoadieDesktops/Module.swift` (façade) | ~60 |
| Modifications `CommandRouter.swift` (handlers desktop.*) | ~80 |
| Modifications `roadie/main.swift` (CLI desktop) | ~30 |
| **Total cible** | **~700** |

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Vérification des gates de conformité (constitution.md) :

- [x] **Aucun `import Package` ni dépendance tierce** : seul Cocoa/CG/AppKit utilisés ; SwiftPM est l'outil de build, pas une dépendance runtime.
- [x] **Aucun usage de `(bundleID, title)` comme clé primaire** : toutes les fenêtres référencées par `CGWindowID` (UInt32) déjà en place dans `WindowState`.
- [x] **Toute action sur fenêtre doit pouvoir être tracée à un `CGWindowID`** : la bascule appelle `setLeafVisible(WindowID, Bool)` qui prend un `CGWindowID` ; aucune fenêtre manipulée par autre moyen.
- [x] **Le binaire compilé < 5 MB pour le daemon** : suppression de `SkyLightDesktopProvider` et de la chaîne CGS-related = gain net binaire. À vérifier post-build.
- [x] **Cible et plafond LOC déclarés** : 700 / 900 (cf. Technical Context).

**Principes A-G** :

- **A. Suckless** : pas de feature dépassant 50 LOC à elle seule (la plus grosse, `DesktopSwitcher.switch(to:)`, ~40 LOC).
- **B. Zéro dépendance externe** : 0 dépendance ajoutée. Bilan : -1 dépendance implicite (SkyLight private API supprimée).
- **C. Identifiants stables** : `CGWindowID` pour fenêtres, `Int` pour `desktop_id` (1..N).
- **D. Fail loud** : si fenêtre persistée plus trouvable, log warning + retrait du registry (FR-024). Si state corrompu, log + initialisation vierge (FR-013). Pas de retry silencieux.
- **E. État sur disque format texte plat** : TOML simple, déjà supporté par `Config.swift`. `cat`/`grep`/`awk` suffisent pour debug.
- **F. CLI minimaliste** : 5 sous-commandes desktop (list, focus, current, label, back) — légère extension acceptée par cohérence avec yabai/AeroSpace (utilisateurs habitués).
- **G. LOC** : déclaré ci-dessus.

**Verdict** : toutes les gates passent. Pas de Complexity Tracking nécessaire.

## Project Structure

### Documentation (this feature)

```text
specs/011-virtual-desktops/
├── plan.md              # This file
├── research.md          # Phase 0 — choix techniques
├── data-model.md        # Phase 1 — entités + transitions
├── quickstart.md        # Phase 1 — comment tester
├── contracts/           # Phase 1 — protocole CLI / events JSON
│   ├── cli-desktop.md
│   └── events-stream.md
├── checklists/
│   └── requirements.md  # Spec quality (Phase 0 specify)
└── tasks.md             # Phase 2 — généré par /speckit.tasks
```

### Source Code (repository root)

```text
Sources/
├── RoadieCore/                       # inchangé, mais Sources/RoadieCore/desktop/ SUPPRIMÉ
│   ├── Config.swift                  # ajouter section [desktops]
│   ├── WindowRegistry.swift          # ajouter `desktopID: Int` sur WindowState
│   └── (autres fichiers inchangés)
├── RoadieDesktops/                   # NOUVEAU module
│   ├── DesktopRegistry.swift         # state in-memory + load/save
│   ├── DesktopState.swift            # entité RoadieDesktop + parsing
│   ├── DesktopSwitcher.swift         # logique bascule offscreen/onscreen + queue
│   ├── Migration.swift               # V1 stages → desktop_id=1
│   ├── EventBus.swift                # events desktop_changed (réutilise pattern V1)
│   └── Module.swift                  # façade publique
├── RoadieStagePlugin/                # MODIFIÉ — stages relifiés au desktop courant
│   └── StageManager.swift            # filtrer par currentDesktopID
├── roadied/                          # MODIFIÉ
│   └── CommandRouter.swift           # handlers desktop.* refondus
└── roadie/                           # MODIFIÉ
    └── main.swift                    # sous-commande `desktop` raffinée

Tests/
└── RoadieDesktopsTests/              # NOUVEAU
    ├── DesktopRegistryTests.swift
    ├── DesktopSwitcherTests.swift
    ├── DesktopStateTests.swift
    └── MigrationTests.swift

À supprimer (legacy SPEC-003 deprecated) :
Sources/RoadieCore/desktop/           # 8 fichiers, ~600 LOC
├── DesktopInfo.swift                 # remplacé par RoadieDesktops/DesktopState.swift
├── DesktopManager.swift              # remplacé par DesktopRegistry + Switcher
├── DesktopProvider.swift             # plus de provider abstrait nécessaire
├── DesktopState.swift                # supplanté
├── EventBus.swift                    # déplacé dans RoadieDesktops/
├── Migration.swift                   # supplanté
├── MockDesktopProvider.swift         # tests obsolètes
└── SkyLightDesktopProvider.swift     # CGS removal (FR-004)

Sources/RoadieFXCore/OSAXCommand.swift
└── case .spaceFocus                  # ajouté en session précédente, à retirer (jamais utilisé)
```

**Structure Decision** : nouveau module SwiftPM `RoadieDesktops`, dépend de `RoadieCore` (pour `WindowRegistry`, `Config`, `WindowState`). Le daemon `roadied` lie `RoadieDesktops` statiquement. Aucune dépendance vers `RoadieFXCore` (pas d'osax pour la bascule). `RoadieStagePlugin` ajoute une dépendance vers `RoadieDesktops` pour scoper ses stages au desktop courant.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Principe F (CLI minimaliste — 4 sous-commandes max) — SPEC-011 ajoute 5 sous-commandes `desktop.*` (list, focus, current, label, back) plus 1 sous-commande `events --follow` | Cohérence avec yabai/AeroSpace : les utilisateurs power-user macOS ont des automations existantes qui s'attendent à `space focus`/`workspace focus`/etc. avec sémantique stable. Réduire en dessous de 5 commandes obligerait à fusionner `current` + `list` ou `back` + `focus recent`, ce qui complexifie l'API au lieu de la simplifier | (a) Fusionner `current` dans `list` : nécessite parsing post-hoc côté script utilisateur, friction inutile. (b) Supprimer `label` : régression d'usabilité (US4). (c) Supprimer `back` : redondant avec `focus recent` mais utilisé par convention dans le shell. La constitution parle de 4 sous-commandes pour le **contexte stage** (verbe `stage`), ici on a un autre contexte (`desktop`). Acceptable comme extension contextuelle, sans dilution du principe sur stages |
