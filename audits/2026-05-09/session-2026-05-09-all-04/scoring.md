# Audit Code v13 — Roadie (session-04)

- **Date** : 2026-05-09
- **Perimetre** : codebase complete
- **Mode** : audit + corrections (3 cycles fix + 1 cycle scoring)
- **Volume** : 57 sources / 36 tests / ~14 000 LOC
- **Tests** : **174 tests / 35 suites — PASS** (vs 157 session-03 = +17 tests directs)
- **Build** : OK

## Note globale : **A**

Progression : session-01 (B) -> 02 (B+) -> 03 (A-) -> **04 (A)**

| Domaine | s01 | s02 | s03 | **s04** |
|---|---|---|---|---|
| Securite / Robustesse | B- | B+ | A- | **A-** (3 @unchecked Sendable subsistent) |
| Complexite algo (Art. XVIII) | B+ | A- | A | **A** |
| Performance | B | B+ | A- | **A-** |
| Qualite / Dette | C+ | C+ | B- | **B** (helper JSONPersistence enrichi) |
| Tests | B | B | B | **A-** (+17 tests directs) |
| Hygiene / Concurrence | B | B | B | **B** |

## 8 fixes appliques sur 3 cycles

### Cycle 1 — Tests directs (T1/T5/T6)
- **T6** : `DisplayTopologyTests.swift` (6 tests : neighbor right/left/up, diagonal rejection, self exclusion)
- **T5** : `FormattersTests.swift` (6 tests : windows, displays, permissions)
- **T-NEW** : `PersistentStageStateTests.swift` (5 tests : stageScope, stageScopeIndex equivalence)

### Cycle 2 — PersistentStageScope perf interne
- **FIX-P8** : `StageStore.swift:335` `updateFrame` ajoute `return` apres match -> O(stages) au lieu d'O(stages * members) en moyenne
- **DOC-P6/P7** : `assign` et `remove` annotees avec complexite + justification (n borne <100)

### Cycle 3 — Migration JSONPersistence
- **FIX-Q7-EXT** : `JSONPersistence.swift` enrichi avec `writeThrowing` / `loadThrowing` + closures de configuration (support `iso8601` et autres)
- **FIX-Q7b** : `RestoreSafetyService.swift` 4 sites migres (writeSnapshot, writeMarker, loadMarker, loadSnapshot) -> -25 lignes dupliquees

## Tests directs ajoutes

| Fichier | Tests | Couverture |
|---|---|---|
| `DisplayTopologyTests.swift` | 6 | DisplayTopology.neighbor (4 directions, edge cases) |
| `FormattersTests.swift` | 6 | TextFormatter.windows / displays / permissions |
| `PersistentStageStateTests.swift` | 5 | stageScope + stageScopeIndex (incluant test d'equivalence) |
| **Total** | **17** | |

## Findings restants

### HAUTE (7)
- **Concurrence (3)** : S9/S10/S11 `@unchecked Sendable` (refactor actor-based session dediee).
- **StateAudit P4** : `repairScopes` triple boucle in-place (refactor risque).
- **God-classes (2)** : Q1 RailController 1912L, Q2 roadie/main 1109L.
- **T4** : RailController sans test direct (UI controller, mocks AppKit complexes).

### MOYENNE (9)
- 4 god-classes restants (Q3-Q6).
- 3 perf StageStore documentees (P6/P7/P9, n borne <100).
- T2/T3 services indirect-only.

### BASSE (2)
- Q9 `CGWindowListCreateImage` deprecated.
- Q-JSON 9 sites dans DaemonSnapshot non migres (typage specifique).

## Conformite Article XVIII

**Verifie**. Toutes les fonctions publiques sur hot path ont une annotation de complexite. Toutes les boucles imbriquees restantes sont :
- Soit aplaties (StateAudit cycle 2 session-02)
- Soit avec exit precoce documente (updateFrame cycle 2 session-04)
- Soit avec borne explicite documentee (assign/remove/mergeDisconnectedScope, PersistentStageScope)
- Soit O(n) reel via index inverse (DaemonSnapshot.snapshot cycle 1 session-03)

## Roadmap (sessions SpecKit dediees)

| Priorite | Theme | Effort | Impact |
|---|---|---|---|
| P0 | Refactor 3 `@unchecked Sendable` -> actors | M | Swift 6 strict concurrency |
| P1 | Decouper RailController + ajouter tests | L | Testabilite, lisibilite |
| P2 | StateAudit.repairScopes simplification + tests | M | Robustesse audit |
| P3 | Migration restante DaemonSnapshot vers JSONPersistence (9 sites) | S | Hygiene |
| P4 | Migration ScreenCaptureKit | M | Future-proof |

## Build & Tests
```
swift build --target RoadieDaemon -> OK
./scripts/with-xcode swift test    -> 174 tests / 35 suites PASS
```
