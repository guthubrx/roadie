# Implementation Plan — SPEC-018 Stages-per-display

**Branch**: `018-stages-per-display` | **Date**: 2026-05-02 (Phase 9 audit-coherence ajoutée 2026-05-03) | **Spec**: [spec.md](spec.md)
**Status**: Implemented + Phase 9 cohérence display×desktop×stage (voir [audit-coherence.md](audit-coherence.md))

## Vue d'ensemble

Refactor du `StageManager` pour indexer les stages par tuple `(displayUUID, desktopID, stageID)` au lieu de `stageID` seul. Migration silencieuse des stages V1 existantes vers le tuple `(mainDisplayUUID, 1)` au premier boot. Compat ascendante stricte si `[desktops] mode = "global"`. Toutes les commandes IPC `stage.*` deviennent automatiquement scopées via résolution curseur → frontmost → primary, avec override optionnel `--display` / `--desktop` pour scripts.

## Technical Context

| Élément | Choix | Justification |
|---|---|---|
| Langage | Swift 5.9 + SwiftPM | Cohérence avec le reste du projet |
| Indexation interne | `[StageScope: Stage]` où `StageScope = (displayUUID, desktopID, stageID)` | Hash O(1), pas de scan linéaire |
| Résolution displayUUID | `CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID)` | API publique CoreGraphics, stable cross-reboot, déjà utilisée par SPEC-012 |
| Résolution scope | `NSEvent.mouseLocation` → `displayContaining(point:)` (priorité 1), fallback frontmost (priorité 2), fallback primary (priorité 3) | Pattern yabai/AeroSpace, pas d'Input Monitoring permission |
| Persistance V2 | Arborescence nested `~/.config/roadies/stages/<displayUUID>/<desktopID>/<stageID>.toml` | Reflète le scope dans l'arborescence, facile à backup |
| Persistance V1 (compat global) | Arborescence flat `~/.config/roadies/stages/<stageID>.toml` | Identique SPEC-002, 0 régression |
| Migration V1 → V2 | One-shot au boot, idempotent, backup automatique | Préserve le travail utilisateur, recovery manuelle possible |
| **Active stage par desktop (Phase 9)** | `activeStageByDesktop: [DesktopKey: StageID]` où `DesktopKey = (displayUUID, desktopID)` | Mémoriser quel stage était actif sur chaque (display, desktop) — sans ce dict, currentStageID scalaire global perd le contexte au desktop_changed |
| **Persistance active per scope (Phase 9)** | `_active.toml` par scope `<stagesDir>/<displayUUID>/<desktopID>/_active.toml` | Survie aux reboots, déjà supporté par `NestedStagePersistence.saveActiveStage(scope:)` |
| **Helper window invariant (Phase 9)** | `WindowState.minimumUsefulDimension = 100` + `isHelperWindow` computed | Filtre les utility windows (Firefox WebExtension 66×20, Grayjay/Electron tooltips, iTerm popovers) qui s'enregistrent comme `AXStandardWindow` sans en être |

### Dépendances inter-spec

- **SPEC-002** (Stage Manager) : prérequis dur — fournit `Stage`, `StageID`, `StageManager`, `Stage.memberWindows`
- **SPEC-011** (Virtual Desktops) : prérequis dur — fournit le concept de desktopID et l'event `desktop_changed`
- **SPEC-012** (Multi-display) : prérequis dur — fournit `Display`, `displayUUID`, `DisplayRegistry`
- **SPEC-013** (Desktop-per-display) : prérequis dur — fournit le mode `per_display` qui motive ce scopage
- **SPEC-014** (Stage Rail UI) : **bloquée par cette spec** — le rail ne peut filtrer correctement les stages par écran sans ce scopage daemon-side

## Constitution Check

| Article | Vérification | Status |
|---|---|---|
| A. Mono-fichier ≤ 200 LOC effectives | Découpage en 4 fichiers : StageScope.swift (~50), StageManager modifs (~150 nettes), StagePersistenceV2.swift (~150), MigrationV1V2.swift (~120) | ✅ |
| B. Zéro dépendance externe non justifiée | Aucune nouvelle dépendance Swift Package | ✅ |
| C'. SkyLight write privé interdit | Lecture seule via CGDisplayCreateUUIDFromDisplayID (API publique) | ✅ |
| D. Pas de `try!`, pas de `print()`, logger structuré | Convention déjà en place | ✅ |
| G. Plafond LOC | Cible 600 / plafond 900 LOC (refactor + tests) | ✅ |

**Aucune violation de gate. Pas de justification spéciale requise.**

## Phase 0 — Research technique

### R-001 : Pattern d'indexation par tuple en Swift

**Décision** : Définir `struct StageScope: Hashable, Sendable, Codable` avec `displayUUID: String`, `desktopID: Int`, `stageID: StageID`. Utiliser `[StageScope: Stage]` comme dict interne. La conformance Hashable est synthétisée automatiquement.

**Rationale** : Type-safe, hash O(1), cohérent avec le pattern existant `WindowID`, `StageID`. Pas besoin de struct séparée pour les sous-clés (DisplayDesktopKey) — le tuple complet est plus lisible.

**Alternatives évaluées** :
- Trois dicts imbriqués `[String: [Int: [StageID: Stage]]]` — verbose, moins lisible, pas d'avantage perf
- Stage avec `scope: StageScope` interne — duplication, plus dur à indexer

### R-002 : Résolution implicite du scope (curseur → frontmost → primary)

**Décision** : Méthode `Daemon.currentStageScope() -> StageScope` exécutée à CHAQUE commande `stage.*`. Cherche dans l'ordre :
1. `NSEvent.mouseLocation` → `displayRegistry.displayContaining(point:)` → si display trouvé, utilise son UUID
2. Fallback : `registry.focusedWindowID` → frame center → `displayContaining(point:)`
3. Fallback ultime : `CGMainDisplayID()` → `displayUUID`

Combine avec `desktopRegistry.currentID(for: displayID)` pour récupérer le desktopID.

**Rationale** : Pattern yabai (`yabai -m query --displays --display` retourne le display sous le curseur). AeroSpace utilise la même heuristique. Pas de permission Input Monitoring.

**Alternatives évaluées** :
- Toujours frontmost en priorité — moins prédictible (la frontmost peut être loin du focus visuel)
- Toujours primary — perd l'utilité du multi-display

### R-003 : Format pasteboard / arborescence persistance V2

**Décision** : `~/.config/roadies/stages/<displayUUID>/<desktopID>/<stageID>.toml`. Le `displayUUID` est utilisé tel quel (string Apple type "37D8832A-2D66-4A47-9B5E-39DA5CF2D85F"). Le dossier `<desktopID>` est nommé par l'int (ex: `1`, `2`).

**Rationale** :
- Arborescence directement parsable (`find ~/.config/roadies/stages -name "*.toml"` donne tous les stages)
- Backup naturel par display (`cp -r <uuid>/ backup/`)
- Stages "orphelines" d'un écran débranché restent visibles sur disque

**Alternatives évaluées** :
- Fichier unique `stages.toml` avec arrays imbriqués — atomicité plus dure (écriture concurrente)
- Indexation par index display (1-N) — index pas stable au reboot vs UUID

### R-004 : Migration V1 → V2 idempotente avec recovery

**Décision** : Au boot V2 (= mode `per_display` activé), si `~/.config/roadies/stages/*.toml` (flat) existe ET `~/.config/roadies/stages.v1.bak/` n'existe pas :
1. `cp -r ~/.config/roadies/stages/ ~/.config/roadies/stages.v1.bak/`
2. Pour chaque `<id>.toml` flat : `mkdir -p stages/<mainDisplayUUID>/1/` puis `mv <id>.toml stages/<mainDisplayUUID>/1/<id>.toml`
3. Émettre event `migration_v1_to_v2` sur EventBus
4. Logger `migrated <N> stages to <displayUUID>/1/`

**Rationale** : Idempotent (le test `stages.v1.bak/ exists` empêche re-migration). Recovery manuelle facile (`mv stages.v1.bak stages` pour rollback).

**Risque** : Si l'utilisateur passe en `per_display` puis revient en `global`, l'arborescence nested reste sur disque mais sera ignorée. Pas de re-flatten automatique ; doc claire dans quickstart.

### R-005 : Override CLI explicite `--display` `--desktop`

**Décision** : Toutes les commandes `stage.*` acceptent `--display <selector>` et `--desktop <id>` côté CLI. Selector display = index 1-N (ordre `roadie display list`) OU UUID. Daemon résout via `DisplayRegistry.display(at:)` ou recherche par UUID.

**Rationale** : Compat scripts BTT/SketchyBar qui peuvent vouloir cibler un écran sans bouger la souris. Optionnel : si absent, fallback sur résolution implicite (R-002).

### R-006 : Compat ascendante mode `global` strict

**Décision** : Si `[desktops] mode = "global"` (default V1), aucune migration n'est faite, l'arborescence reste flat, et StageManager utilise une stratégie `FlatStagePersistence` qui ignore le scope display/desktop. Le tuple interne devient `(emptyUUID, 0, stageID)` (sentinelle), mais le stockage disque reste plat.

**Rationale** : Zéro régression pour les utilisateurs mono-display. Le mode `per_display` est un opt-in conscient.

## Phase 1 — Design & Contracts

### Data model

Voir [data-model.md](data-model.md). Entités principales :

- `StageScope` : tuple Hashable (displayUUID, desktopID, stageID)
- `Stage` : inchangée (réutilise SPEC-002)
- `StageManager` (modifié) : refactor du StageManager existant
- `StagePersistenceV2` : protocole avec 2 implémentations (Flat, Nested)
- `MigrationV1V2` : composant one-shot

### Contracts IPC

Voir [contracts/](contracts/). Contrats étendus :

- [`cli-stage-list.md`](contracts/cli-stage-list.md) — `stage.list` avec scope implicite + `--display`/`--desktop` override + champs réponse étendus
- [`cli-stage-mutations.md`](contracts/cli-stage-mutations.md) — `stage.assign`, `stage.switch`, `stage.create`, `stage.delete`, `stage.rename` avec scope
- [`events-stream-stages.md`](contracts/events-stream-stages.md) — events `stage_changed` etc. avec `display_uuid` + `desktop_id` dans le payload, et nouvel event `migration_v1_to_v2`

### Quickstart

Voir [quickstart.md](quickstart.md). Steps :
1. Activation : `[desktops] mode = "per_display"` dans `~/.config/roadies/roadies.toml`
2. Migration auto au premier boot (rapport sur stderr daemon)
3. Test isolation : créer une stage sur display A, vérifier absence sur display B
4. Recovery V1 : restoration manuelle depuis `stages.v1.bak/`

## Phase 2 — Plan d'implémentation

### Modules à créer/modifier

```
Sources/RoadieStagePlugin/
  StageScope.swift                  — NEW : struct tuple Hashable (~50 LOC)
  StageManager.swift                — MODIFIED : `stages: [StageScope: Stage]`, méthodes scopées (~150 LOC nettes)
  StagePersistenceV2.swift          — NEW : protocol + FlatStagePersistence + NestedStagePersistence (~180 LOC)
  MigrationV1V2.swift               — NEW : one-shot migrator (~120 LOC)

Sources/roadied/
  CommandRouter.swift               — MODIFIED : extension stage.* pour scope implicite + override --display --desktop (~80 LOC nettes)
  main.swift                        — MODIFIED : init StageManager selon mode + appel MigrationV1V2 (~30 LOC nettes)

Sources/roadie/
  main.swift                        — MODIFIED : ajout flags --display --desktop sur stage.* (~40 LOC)

Tests/RoadieStagePluginTests/
  StageScopeTests.swift             — NEW : Hashable, Codable, init (~50 LOC)
  StageManagerScopedTests.swift     — NEW : isolation cross-display, mutations scopées (~200 LOC)
  MigrationV1V2Tests.swift          — NEW : migration idempotente, backup, rollback (~150 LOC)
  StagePersistenceV2Tests.swift     — NEW : flat vs nested IO (~120 LOC)
```

**Cumul estimé** : ~600 LOC production + ~520 LOC tests = ~1120 LOC. Production sous le plafond G (900). Tests hors plafond (Article G ne compte pas les tests).

### Build pipeline

- Pas de nouveau target SPM (réutilise `RoadieStagePlugin` existant)
- Pas de nouvelle dépendance externe
- Tests intégrés à `swift test --filter RoadieStagePluginTests`

### Stratégie de tests

- **Unit tests** :
  - `StageScopeTests` : Hashable contract (eq → hash égal), Codable round-trip, init avec sentinel
  - `MigrationV1V2Tests` :
    - Cas heureux : 5 stages flat → 5 stages dans `<uuid>/1/`
    - Idempotence : 2 boots successifs → migration faite 1 seule fois
    - Recovery : `stages.v1.bak/` présent → pas de re-migration
    - Erreur disque : permission refusée → flag `migration_pending: true`, fallback flat
  - `StageManagerScopedTests` :
    - 2 stages de même ID sur 2 scopes différents coexistent
    - `stage.list` filtre correctement par scope courant
    - `stage.assign` crée dans le bon scope (lazy create)
- **Integration tests** :
  - Daemon en mode `per_display` : créer stage curseur sur D1, vérifier absent quand curseur sur D2 via `nc -U socket`
  - Migration au boot daemon : préparer `stages/2.toml`, démarrer daemon, vérifier `stages/<uuid>/1/2.toml` créé
- **Régression** :
  - `swift test --filter RoadieStagePluginTests` doit garder 100% de la suite existante (mode global = comportement V1)

### Performance budget

| Métrique | Cible | Mesuré comment |
|---|---|---|
| Latence résolution scope | < 5 ms p95 | Bench dans `currentStageScope()` |
| Latence migration 50 stages | < 500 ms | Test acceptance avec `time` |
| RSS daemon stable | ±10% sur 8h | `ps -o rss` avant/après stress test |

## Phase 3 — Risques opérationnels

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Migration corrompt les stages | Bas (idempotent + backup) | Élevé | Backup + flag migration_pending si fail, doc recovery |
| Curseur hors-écran race | Moyen | Bas | Fallback frontmost → primary, jamais bloquant |
| Hot-switch mode chaotique | Bas | Moyen | Doc "redémarrer le daemon", best effort |
| displayUUID change après changement carte vidéo | Bas | Moyen | Stages préservées orphelines, doc reassign manuel |
| Compat tests SPEC-002 cassée | Moyen | Élevé | CI : suite SPEC-002 obligatoire en mode global |

## Phase 4 — Plan de découpage en livrables

V1 (MVP) couvre US1, US2, US3, US5 :
- StageScope + StageManager modifié + persistence Flat/Nested + Migration
- IPC scope implicite (sans override `--display`)
- Compat global mode
- Coherence rail (le rail SPEC-014 reçoit déjà des stages déjà filtrées)

V1.1 (post-MVP) couvre US4 :
- Override CLI `--display` / `--desktop`

V1.2 :
- Hot-switch de mode amélioré (re-flatten/re-nest auto)

L'ordre permet de livrer d'abord la valeur principale (isolation par écran) puis d'itérer sur les détails power-user.

## Annexes

- Référence pattern yabai : `yabai -m query --displays --display` (selector display sous le curseur)
- Référence pattern AeroSpace : `aerospace list-workspaces --monitor mouse`
- Référence SPEC-013 : `Sources/RoadieDesktops/DesktopRegistry.swift` — DesktopRegistry expose déjà `currentID(for: CGDirectDisplayID)`
- Discussion design 2026-05-02 : conversation Claude Code (description utilisateur exhaustive en input)
