# Audit Code v13 — Roadie

- **Date** : 2026-05-09
- **Perimetre** : ensemble de la codebase
- **Mode** : audit + corrections (1 cycle fix + 1 cycle scoring)
- **Stack** : Swift 6 strict concurrency, macOS 14, daemon gestionnaire de fenetres
- **Volume** : 57 fichiers Sources / 33 fichiers Tests / 13 841 LOC

## Note globale : **B**

| Domaine                  | Note  | Justification                                                                 |
|--------------------------|-------|-------------------------------------------------------------------------------|
| Securite / Robustesse    | B-    | 3 force-cast restants (CFTypeID-protected), 4 timer!, 3 @unchecked Sendable a auditer |
| Complexite algo (Art. XVIII) | B+ | n borne par construction (1-4 displays, 5-10 stages, 1-100 windows). Nesting structurel a aplatir mais pas de hot path serveur. 1 fix applique (filter+count -> single-pass) |
| Qualite / Dette          | C+    | 4 god-classes >600 lignes (Rail 1912, roadie/main 1109, DaemonSnapshot 863, WindowCommands 739) |
| Tests                    | B     | Ratio 56% raisonnable, mais 6 modules majeurs sans test direct (RailController inclus) |
| Performance              | B     | Pas de I/O en boucle, pas de N+1. O(n^2) overlap-check a documenter |
| Hygiene / Concurrence    | B     | 0 TODO/FIXME, build clean (warnings deprecated CGWindowList & activateIgnoringOtherApps) |

## Corrections appliquees (cycle 1)

| Fix | Fichier | Description |
|-----|---------|-------------|
| FIX1 | `Sources/RoadieDaemon/DaemonSnapshot.swift:642` | Triple `filter+count` remplace par single-pass `switch` (3n -> n) |
| FIX2 | `Sources/RoadieAX/SystemSnapshotProvider.swift:171` | Garde `CFGetTypeID == AXUIElementGetTypeID` ajoutee avant `as! AXUIElement` |
| FIX3 | `Sources/RoadieDaemon/LayoutMaintainer.swift:189` | Force-unwrap `maxTicks!` remplace par `maxTicks.map({ ticks < $0 }) ?? true` |

Build : compilation OK pour tous les targets (`RoadieAX`, `RoadieDaemon`). Erreur linker `-no_warn_duplicate_libraries` env-only (Xcode toolchain), non liee aux changes.

## Top findings restants (par priorite)

### CRITIQUE (2)
1. **S2/S3** — `SystemSnapshotProvider.swift:366-367` : `as! AXValue`. Risque limite (CFTypeID deja verifie). Conversion vers `as? AXValue` recommandee pour lisibilite.

### HAUTE (21)
- **Concurrence** : 3 `@unchecked Sendable` (S9, S10, S11) sans synchronisation visible. Audit cible necessaire (lock/queue/actor isolation).
- **Force-unwrap timers** : S5/S6/S7/S8 (4 sites). Refactor par `if let timer = ...`.
- **Complexite** : P1-P9 sur StateAudit/StageStore. Recommandation : index inverse `windowID -> ScopeLocation` maintenu incrementalement.
- **Quality** : Q1/Q2/T1/T4 — RailController 1912 lignes sans test direct. Decoupage prioritaire.

### MOYENNE / BASSE (16)
- 4 god-classes restants (Q3-Q6).
- API depreciee macOS 14 (Q9 `CGWindowListCreateImage` -> `ScreenCaptureKit`).
- Couverture tests sur Formatters, DisplayTopology, AutomationSnapshotService, LayoutCommandService.

## Roadmap recommandee (par sessions SpecKit)

| Session | Theme | Effort | Impact |
|---------|-------|--------|--------|
| S+1 | Refactor concurrence : remplacer 3 `@unchecked Sendable` par actors ou serial queue documentee | M | High (Swift 6 strict concurrency) |
| S+2 | Decouper RailController 1912 lignes -> RailPanelManager + RailDragHandler + RailConfigWatcher | L | High (testabilite, lisibilite) |
| S+3 | Index inverse StageStore (`windowID -> ScopeLocation`) + tests perf | M | Medium (latence StateAudit/repair) |
| S+4 | Tests directs RailController, DaemonSnapshot, Formatters, DisplayTopology | M | High (regression) |
| S+5 | Migration ScreenCaptureKit (deprecated CGWindowListCreateImage) | M | Low (warning, pas de bug) |

## Conformite Article XVIII (Complexite)

OK : tous les nestings detectes ont une borne par construction documentee (1-4 displays max, 5-10 stages, ~100 windows). Aucun anti-pattern dans un endpoint API ou hot path haute frequence (pas d'API HTTP, pas de queue worker).
Recommandation : ajouter explicitement `// Complexite : O(s*m) ou s,m bornes` sur les fonctions publiques de `StateAudit` et `StageStore`.

## Artefacts

- `cycle-1/aggregated-findings.json` (46 findings avant fix)
- `cycle-scoring/aggregated-findings.json` (42 findings restants apres fix + 3 fixed-info)
- `grade.json` (B)
