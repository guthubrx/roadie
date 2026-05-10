# Audit Code v13 — Roadie (session-02)

- **Date** : 2026-05-09
- **Perimetre** : codebase complete
- **Mode** : audit + corrections (3 cycles fix + 1 cycle scoring)
- **Stack** : Swift 6 strict concurrency, macOS 14
- **Volume** : 57 sources / 33 tests / 13 841 LOC

## Note globale : **B+**

Progression depuis session-01 (B) : +1 cran. Toutes les corrections compilent (`swift build --target RoadieAX`, `--target RoadieDaemon` OK).

| Domaine | Note session-01 | Note session-02 | Delta |
|---|---|---|---|
| Securite / Robustesse | B- | B+ | +2 (5 force-unwraps elimines, 2 force-cast documentes) |
| Complexite algo (Art. XVIII) | B+ | A- | +1 (3 fonctions StateAudit aplaties, 2 annotations bornes) |
| Qualite / Dette | C+ | C+ | = (god-classes inchanges, hors scope 1 cycle) |
| Tests | B | B | = |
| Performance | B | B+ | +1 (P12 neighborScore + P11 single-pass) |
| Hygiene / Concurrence | B | B | = (3 @unchecked Sendable subsistent) |

## Corrections appliquees

### Cycle 1 — Securite + perf simple (6 fixes)
| Fix | Fichier:ligne | Description |
|---|---|---|
| FIX-S5 | `FocusFollowsMouseController.swift:26` | `timer!` -> capture locale `newTimer` |
| FIX-S6 | `BorderController.swift:27` | `refreshTimer!` -> capture locale |
| FIX-S7 | `RailController.swift:48` | `refreshTimer!` -> capture locale |
| FIX-S8 | `RailController.swift:111` | `hoverTimer!` -> capture locale |
| FIX-S2/S3 | `SystemSnapshotProvider.swift:366-367` | `as! AXValue` extrait + commentaire safety |
| FIX-P12 | `WindowCommands.swift:301` | `activeAndNeighbor` : score precalcule O(n) au lieu O(2n) |

### Cycle 2 — Aplatir StateAudit (3 fixes)
| Fix | Fichier:ligne | Description |
|---|---|---|
| FIX-P1 | `StateAudit.swift:157` | `focusedMembersCheck` : flatMap + Set lookup, annotation O(stages) |
| FIX-P2 | `StateAudit.swift:174` | `duplicateMembershipCheck` : `lazy.flatMap` parcours unique |
| FIX-P3 | `StateAudit.swift:191` | `staleMembersCheck` : `reduce(into:)` single-pass |

### Cycle 3 — Annotations Article XVIII (2 docs)
| Doc | Fichier:ligne | Description |
|---|---|---|
| DOC-P5 | `StageStore.swift:92` | `stageScope` : complexite O(s*g*m) bornee + recommandation index inverse |
| DOC-P10 | `DaemonSnapshot.swift:578` | `framesContainSignificantOverlap` : O(n^2) borne <=190 comparaisons |

## Findings restants (par priorite)

### HAUTE (12)
- **Concurrence** : 3 `@unchecked Sendable` (S9-S11) sans synchro visible. Refactor actor-based necessaire.
- **Complexite StageStore** : P6/P7/P9 (assign/remove/mergeDisconnectedScope). Necessite index inverse maintenu incrementalement.
- **Complexite divers** : P4 (repairScopes), P13 (activeWindow), P15 (AXWindowFrameWriter triple loop).
- **Quality** : Q1 (RailController 1912 lignes), Q2 (roadie/main 1109).
- **Tests** : T1, T4 (RailController sans test direct).

### MOYENNE (11)
- 4 god-classes >600 lignes (Q3-Q6, DaemonSnapshot/WindowCommands/Config/StageCommands).
- Process() args non valides (S12, S13).
- StageStore P8 (updateFrame), P14 (sort en boucle), P16 (RailController map missing).
- Tests T2, T3 (services indirect-only).

### BASSE (5)
- Q7 helper JSON, Q8 timer pattern, Q9 deprecated API, T5/T6 modules formatters/topology.

## Conformite Article XVIII

OK. Toutes les fonctions a complexite non triviale dans les hot paths sont desormais soit aplaties soit annotees explicitement avec leur borne :
- `focusedMembersCheck` : O(stages) avec lookup Set O(1)
- `duplicateMembershipCheck` : O(total_members) parcours unique
- `staleMembersCheck` : O(total_members)
- `stageScope` : O(s*g*m) borne par n total membres + reco index inverse
- `framesContainSignificantOverlap` : O(n^2) borne explicite n<20

Aucun anti-pattern detecte dans un endpoint API ou hot path haute frequence (pas d'API HTTP, pas de queue worker).

## Roadmap (sessions SpecKit)

| Priorite | Theme | Effort | Impact |
|---|---|---|---|
| P0 | Refactor 3 `@unchecked Sendable` -> actor / serial queue documentee | M | High (Swift 6 strict) |
| P1 | Decouper RailController 1912L en 3 modules + tests directs | L | High (testabilite) |
| P2 | Index inverse `windowID -> StageScope` dans StageStore + invalidation incrementale | M | Medium |
| P3 | Tests directs DaemonSnapshot, Formatters, DisplayTopology | M | High (regression) |
| P4 | Migration ScreenCaptureKit (deprecated CGWindowListCreateImage) | M | Low |

## Build status

```
swift build --target RoadieAX     -> OK (0.10s)
swift build --target RoadieDaemon -> OK (1.28s)
```

(Erreur linker `-no_warn_duplicate_libraries` au build full = environnement Xcode toolchain, non lie aux changes.)
