# Implementation Plan: Migration mono-binaire (fusion roadied + roadie-rail)

**Branch**: `024-monobinary-merge` | **Date**: 2026-05-04 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/024-monobinary-merge/spec.md`

## Summary

Fusionner les deux exécutables actuels (`roadied` daemon launchd + `roadie-rail` `.app` GUI) en un unique binaire `roadied` qui héberge à la fois la logique tiling et l'UI rail SwiftUI. Le binaire CLI `roadie` reste séparé et continue à parler au process unifié via le socket Unix existant. La séparation **logique** par modules Swift (RoadieCore, RoadieTiler, RoadieStagePlugin, RoadieDesktops, RoadieRail) est strictement préservée. Le code retiré (RailIPCClient + serveur IPC events + parseur TOML dupliqué + helpers tolérants) doit produire un solde LOC net négatif (cible ≥ −150 LOC).

## Technical Context

**Language/Version** : Swift 5.9, swift-tools 5.9
**Primary Dependencies** : AppKit, ApplicationServices, CoreGraphics, ScreenCaptureKit, SwiftUI, Combine, **TOMLKit** (déjà en place, internalisable V2 si scope reste raisonnable, art B' constitution-002)
**Storage** : `~/.config/roadies/roadies.toml` (config), `~/.roadies/daemon.sock` (IPC public), `~/.local/state/roadies/` (logs JSON-lines), `~/.roadies/stages.v1.bak/` (backups stages)
**Testing** : XCTest (test pyramid art H' constitution-002 : unitaire + intégration + acceptation manuelle)
**Target Platform** : macOS 14 (Sonoma) minimum, validé sur Tahoe 26 (machine dev)
**Project Type** : single — projet Swift Package Manager, exécutables + libraries
**Performance Goals** :
- Latence p95 apparition rail sur hover edge ≤ 100 ms (SC-006)
- Démarrage process → rail visible (mode always-visible) ≤ 3 s (SC-007)
- Aucune dégradation perceptible vs V1 sur thumbnails (capture rate 2 s × N fenêtres)

**Constraints** :
- Codesign ad-hoc avec `roadied-cert` uniquement (pas de Developer ID)
- Pas de SIP off requis (le daemon core reste sur AX + CGS read-only, art C' constitution-002)
- Compat ascendante CLI/socket/events stricte (FR-008, contrat figé)
- Pas de nouvelle dépendance externe non justifiée (art B')

**Scale/Scope** :
- Codebase actuel : 14 570 LOC effectives (audit `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`)
- Cible delta migration : **−150 LOC nettes** (suppression > ajout)
- Plafond strict ajout : **+100 LOC** (en cas de création d'un EventBus minimal si l'existant ne suffit pas)
- Bilan attendu : net entre −150 et −300 LOC

### Cible / Plafond LOC pour la migration (art G' constitution-002)

- **Cible** : delta net ≤ **−150 LOC effectives** sur l'ensemble du projet.
- **Plafond strict** : delta net ≤ **+50 LOC** (si dépassement → refactor obligatoire OU justification ADR).

Mesure de référence avant/après :
```bash
find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
```

Composantes attendues du delta :
- **Suppressions** :
  - `Sources/RoadieRail/Networking/RailIPCClient.swift` : ~150 LOC
  - `Sources/RoadieRail/Networking/EventStream.swift` (consommation IPC events) : ~80 LOC
  - `Sources/RoadieRail/main.swift` (entry point séparé) : ~10 LOC
  - `Sources/RoadieRail/AppDelegate.swift` (PID lock + lifecycle propre) : ~30 LOC partiellement transférées
  - `Sources/RoadieRail/RailController.swift` parsing TOML dupliqué (`RailConfig.load()`) : ~50 LOC migrées vers Config partagé
  - Helpers `decodeBool/Int/String` (cast direct possible avec accès in-process) : ~30 LOC
  - Serveur IPC events côté daemon (events publiés sur le bus public ne sont plus dupliqués pour la consommation rail) : ~50 LOC
  - Code TCC duplication (rail demandait sa propre grant Screen Recording) : ~30 LOC
- **Ajouts** :
  - Branchement RailController dans `Sources/roadied/main.swift` bootstrap : ~20 LOC
  - Adapter EventBus → RoadieRail (ou utilisation directe de l'EventBus existant) : ~30 LOC
  - Cleanup script V1 dans `install-dev.sh` : ~30 LOC bash (n'entrent pas dans le LOC Swift)

**Bilan estimé** : −430 ajouts +80 = **−350 LOC nettes Swift** (large marge sous la cible).

## Constitution Check

*GATE: doit passer avant Phase 0 research. Re-check après Phase 1 design.*

Vérification des gates de la constitution-002 v1.3.0 :

| Gate | Status | Notes |
|------|--------|-------|
| Aucun fichier Swift > 200 LOC effectives | ⚠ pré-existant | Quelques fichiers du daemon dépassent déjà (StageManager.swift, main.swift). Cette spec ne les aggrave pas. À traiter dans une session de refactor dédiée. |
| Aucune dépendance externe non justifiée | ✓ | Aucune nouvelle dépendance ajoutée. TOMLKit reste l'unique externe (justifié pré-existant). |
| CGWindowID utilisé partout | ✓ | Migration ne touche pas les clés de fenêtres. |
| FR-005 art C' : aucun symbole CGS d'écriture linké au daemon core | ✓ | Migration ne change pas le linkage des modules SIP-off (ils restent .dynamicLibrary séparées). |
| Tiler protocol ≥ 2 implémentations | ✓ | BSP + Master-Stack toujours présents, intacts. |
| StagePlugin séparé (compile sans Stage si flag off) | ✓ | Architecture modulaire préservée. |
| Logger structuré JSON-lines, pas de `print()` | ✓ | Convention maintenue dans le code migré. |
| Tests unitaires existants pour code pur | ✓ | Tests Tiler/Tree/Config inchangés. |
| LOC effectives < 4 000 plafond strict | ✗ pré-existant | Projet à 14 570 LOC. Plafond historique SPEC-002 dépassé depuis SPEC-014/018 (rail SwiftUI). Cette spec **réduit** le LOC ; un ADR de relèvement de plafond a été produit ailleurs (à confirmer en Phase 0). |
| Audit `/audit` mesure et rapporte LOC | ✓ | Pratique en place. |

### Gates spec-locales art C' (modules SIP-off)

| Condition | Status |
|-----------|--------|
| Daemon core 100 % fonctionnel sans modules chargés | ✓ inchangé |
| Modules `.dynamicLibrary` jamais liés statiquement | ✓ inchangé (Package.swift) |
| Daemon ne crash pas si SIP fully on | ✓ inchangé |
| Scripting addition installée par script user séparé | ✓ inchangé |
| Chaque module a sa SPEC dédiée | ✓ historique |
| Module désactivable via flag config | ✓ inchangé |

### Justification du dépassement de plafond pré-existant

Le projet a dépassé les 4 000 LOC du plafond initial SPEC-002 en intégrant SPEC-014 (rail UI SwiftUI = 2 733 LOC), SPEC-018, SPEC-022. Ces dépassements ont été acceptés via SPEC dédiées avec ADR implicite. **Cette spec va dans le sens contraire** (réduction) et n'aggrave pas le dépassement.

→ **Aucune nouvelle violation introduite par cette spec. Pas de Complexity Tracking nécessaire.**

## Project Structure

### Documentation (this feature)

```text
specs/024-monobinary-merge/
├── plan.md              # Ce fichier
├── research.md          # Phase 0 — résolution des unknowns techniques
├── data-model.md        # Phase 1 — entités EventBus, RailController integration
├── quickstart.md        # Phase 1 — procédure migration utilisateur V1→V2
├── contracts/           # Phase 1 — contrat IPC public préservé, contrat EventBus interne
│   ├── ipc-public-frozen.md
│   └── eventbus-internal.md
├── checklists/
│   └── requirements.md  # Phase 1 — checklist quality
└── tasks.md             # Phase 2 (non créé par /speckit.plan)
```

### Source Code (repository root)

État actuel :
```text
Sources/
├── roadied/                  # binaire daemon principal
│   ├── main.swift            # bootstrap NSApp.accessory + Daemon
│   ├── CommandRouter.swift   # routes IPC public (CLI client)
│   ├── FXLoader.swift        # SPEC-004 chargement modules SIP-off
│   └── ...
├── roadie/                   # binaire CLI (parle au socket)
│   └── main.swift
├── RoadieRail/               # binaire séparé GUI .accessory ❌ à fusionner
│   ├── main.swift            # entry point indépendant
│   ├── AppDelegate.swift     # PID lock + lifecycle propre
│   ├── RailController.swift  # orchestrateur
│   ├── Networking/
│   │   ├── RailIPCClient.swift     # ❌ supprime (accès in-process)
│   │   ├── EventStream.swift       # ❌ supprime (subscribe in-process)
│   │   └── ThumbnailFetcher.swift  # ✓ garde, refactor (in-process direct)
│   ├── Views/StageRailPanel.swift  # ✓ garde
│   ├── Hover/{EdgeMonitor,FadeAnimator}.swift  # ✓ garde
│   └── Renderers/*.swift     # ✓ garde
├── RoadieCore/               # protocol + EventBus + WindowState
├── RoadieTiler/              # tiling logic
├── RoadieStagePlugin/        # stages logic
├── RoadieDesktops/           # virtual desktops (a déjà un EventBus actor)
└── RoadieFXCore + Roadie{Animations,Borders,Blur,...}/  # modules SIP-off (intacts)
```

État cible (post-migration) :
```text
Sources/
├── roadied/                  # binaire UNIQUE GUI .accessory
│   ├── main.swift            # bootstrap NSApp + Daemon + RailController
│   ├── CommandRouter.swift   # routes IPC public (inchangé)
│   ├── FXLoader.swift        # inchangé
│   └── RailIntegration.swift # NOUVEAU ~30 LOC : branche RailController au bootstrap
├── roadie/                   # binaire CLI (inchangé)
├── RoadieRail/               # devient bibliothèque liée à roadied (plus d'executable)
│   ├── (main.swift SUPPRIMÉ)
│   ├── (AppDelegate.swift SUPPRIMÉ — logique transférée à RailIntegration)
│   ├── RailController.swift  # refactor : @MainActor, init avec EventBus injecté
│   ├── Networking/
│   │   ├── (RailIPCClient.swift SUPPRIMÉ)
│   │   ├── (EventStream.swift SUPPRIMÉ)
│   │   └── ThumbnailFetcher.swift  # refactor : access direct au cache thumbnails
│   ├── Views/, Hover/, Renderers/, Models/  # inchangés
│   └── ...
└── (autres modules inchangés)
```

**Structure Decision** : préserver la séparation logique modulaire SwiftPM. Le module `RoadieRail` passe de `executable` à `library` dans `Package.swift`. Le binaire `roadied` ajoute une dépendance sur `RoadieRail`. Aucun module interne (RoadieCore, RoadieTiler, etc.) n'est modifié structurellement.

### Modifications `Package.swift`

```swift
// AVANT
.executable(name: "roadie-rail", targets: ["RoadieRail"]),
// ...
.executableTarget(name: "RoadieRail", dependencies: ["RoadieCore"]),
.executableTarget(name: "roadied", dependencies: ["RoadieCore", "RoadieTiler", ...]),

// APRÈS
// (suppression du product roadie-rail)
.target(name: "RoadieRail", dependencies: ["RoadieCore"]),  // était executableTarget → target
.executableTarget(name: "roadied", dependencies: ["RoadieCore", "RoadieTiler", "RoadieRail", ...]),  // ajout
```

## Complexity Tracking

> **Rempli ONLY si Constitution Check a des violations à justifier**

| Violation | Pourquoi nécessaire | Alternative simple rejetée parce que |
|-----------|---------------------|--------------------------------------|
| (Aucune nouvelle violation introduite — voir tableau Constitution Check ci-dessus) | — | — |

Note : la violation pré-existante de plafond LOC (14 570 vs 4 000) n'est pas créée par cette spec. Cette spec **réduit** le LOC. Un suivi de relèvement formel du plafond pour le projet entier est un sujet séparé (à traiter en SPEC dédiée si nécessaire, ou via amendement constitution-002).
