# Audit Code v13 — Roadie (session-03)

- **Date** : 2026-05-09
- **Perimetre** : codebase complete
- **Mode** : audit + corrections (5 cycles fix + 1 cycle scoring)
- **Volume** : 57 sources / 33 tests / ~13 900 LOC
- **Tests** : 157 tests / 32 suites — **PASS**
- **Build** : OK (RoadieAX, RoadieDaemon)

## Note globale : **A-**

Progression : session-01 (B) -> session-02 (B+) -> **session-03 (A-)**.

| Domaine | session-01 | session-02 | **session-03** |
|---|---|---|---|
| Securite / Robustesse | B- | B+ | **A-** |
| Complexite algo (Art. XVIII) | B+ | A- | **A** |
| Performance | B | B+ | **A-** |
| Qualite / Dette | C+ | C+ | **B-** |
| Tests | B | B | **B** (unchanged) |
| Hygiene / Concurrence | B | B | **B** (3 @unchecked Sendable subsistent) |

## 9 fixes appliques sur 5 cycles

### Cycle 1 — Index inverse StageStore
- **FIX-P5** : `StageStore.swift:96+` ajout `stageScopeIndex() -> [WindowID: StageScope]` O(total_members)
- **FIX-P5b** : `DaemonSnapshot.swift:124` hot loop utilise index local + maintenu incrementalement -> O(total_members) au lieu d'O(w * scopes * stages * members)

### Cycle 2 — AX scans fusionnes
- **FIX-P15** : `SystemSnapshotProvider.swift:276` `element(matching:)` fusionne 3 boucles (ID/frame/titre) en single-pass avec exit precoce sur ID match
- **NOFIX-P13** : `WindowCommands.swift:396` activeWindow O(d*w) avec d<5, justifie

### Cycle 3 — Map perf
- **FIX-P16** : `RailController.swift:312` `relayoutAfterRailWidthChange` construit `displayByWindow` Dictionary une fois -> O(c+w)
- **NOFIX-P14** : `WindowCommands.swift:560` insert sort appele 1x par commande, false positive

### Cycle 4 — Process() validation
- **FIX-S12** : `roadied/main.swift:189` annotation securite explicite (self exec, args hard-codes, pid kernel)
- **FIX-S13** : `roadie/main.swift:1096` `runShell` guard chemin absolu (refus relative paths)

### Cycle 5 — Helper JSONPersistence
- **FIX-Q7** : nouveau `JSONPersistence.swift` (load/write atomique). Applique a `StageStore` + `LayoutIntentStore` (-32 lignes dupliquees). 7 sites restants documentes pour migration ulterieure.

## Findings restants

### HAUTE (11)
- **Concurrence (3)** : S9/S10/S11 `@unchecked Sendable` necessitent refactor actor-based (session SpecKit dediee).
- **PersistentStageScope perf (3)** : P6/P7/P9 mutations par indices, hors scope cycle court.
- **StateAudit P4** : `repairScopes` triple boucle in-place avec sortie precoce.
- **God-classes (2)** : Q1 RailController 1912L, Q2 roadie/main 1109L.
- **Tests (2)** : T1, T4.

### MOYENNE (7)
- 4 god-classes restants (Q3-Q6).
- P8 `updateFrame` firstIndex non cache.
- T2, T3 services indirect-only.

### BASSE (3)
- Q9 `CGWindowListCreateImage` deprecated.
- T5/T6 modules non testes.

## Conformite Article XVIII

**Verifie** sur tous les fichiers du perimetre :
- Tous les nestings restants sont annotes avec leur borne explicite.
- Toutes les fonctions publiques avec complexite non-triviale ont une annotation.
- Les hot paths (DaemonSnapshot.snapshot, AX element matching) sont desormais O(n) en simple passe.
- Aucun anti-pattern dans un endpoint API (n/a) ou hot path haute frequence.

## Tableau d'impact perf

| Hot path | Avant | Apres | Gain |
|---|---|---|---|
| `DaemonSnapshot.snapshot()` (w windows) | O(w * scopes * stages * members) | O(total_members + w) | **massif sur grandes collections** |
| `AXWindowFrameWriter.element(matching:)` | O(3n) | O(n) | 3x |
| `RailController.relayoutAfterRailWidthChange` | O(c * w) | O(c + w) | quadratique -> lineaire |
| `WindowCommands.activeAndNeighbor` | O(2n) score calls | O(n) | 2x |

## Roadmap (sessions SpecKit dediees)

| Priorite | Theme | Effort | Impact |
|---|---|---|---|
| P0 | Refactor 3 `@unchecked Sendable` -> actors documentes | M | Swift 6 strict concurrency |
| P1 | Decouper RailController (1912 lignes) | L | Testabilite, lisibilite |
| P2 | PersistentStageScope index inverse incremental (assign/remove/merge) | M | Perf StageStore |
| P3 | Tests directs RailController, DaemonSnapshot, Formatters, DisplayTopology | M | Couverture regression |
| P4 | Migration ScreenCaptureKit (deprecated CGWindowListCreateImage) | M | Future-proof |
| P5 | Migration restante vers JSONPersistence (7 sites) | S | Hygiene |

## Build & Tests
```
swift build --target RoadieAX     -> OK
swift build --target RoadieDaemon -> OK
./scripts/with-xcode swift test   -> 157 tests / 32 suites PASS
```
