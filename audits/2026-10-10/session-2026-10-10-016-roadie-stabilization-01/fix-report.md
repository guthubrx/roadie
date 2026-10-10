# Rapport des cycles de correction - audit v14 SPEC-016

## Résumé
- Cycles : 1 cycle fix (`cycle-1/`) + 1 cycle de scoring en lecture seule (`cycle-scoring/`).
- CRITICAL/HIGH à corriger : 0 (aucun après agrégation). Sélection étendue aux MEDIUM/LOW à défaut net, vérifiables par tests (décision documentée dans `cycles.log`).
- Findings sélectionnés : 7 ; corrigés : 7 ; bloqués : 0 ; disjoncteur : non déclenché (1 seconde tentative sur TEST-002, assertion de test seulement).
- Commits : aucun (AUTO_COMMIT=false, imposé par l'orchestrateur appelant qui commitera).
- Tests : build OK ; `./scripts/test` 626 tests / 69 suites verts (620 avant, +6).

## Fixed (non commité)
| Finding (cycle-1) | Titre | Fichiers | Vérification |
|---|---|---|---|
| PERF-001 | Config du rail relue à chaque calcul de marges (FR-023) | Sources/RoadieDaemon/RailSettings.swift ; Tests/RoadieDaemonTests/ConfigTests.swift | test `railSettingsFileIsReparsedOnlyWhenItChanges` (rouge sans correction) |
| PERF-003 | O(n²) des états de présentation dans `windowSnapshots` | Sources/RoadieDaemon/AutomationSnapshotService.swift ; Sources/RoadieDaemon/WindowPresentationStateResolver.swift | tests AutomationSnapshot + résolveur (comportement constant) |
| QUAL-008 | Marqueur de reprise illisible pris pour absent et écrasé sans copie (FR-015, FR-037) | Sources/RoadieDaemon/RestoreSafetyService.swift ; Tests/RoadieDaemonTests/RestoreSafetyServiceTests.swift | test `startRunRecoversWhenRunMarkerIsUnreadable` (rouge sans correction) |
| MIN-002 | `fx.rail.header.height/width` sans effet non signalées (FR-034) | Sources/RoadieCore/Config.swift ; Tests/RoadieDaemonTests/ConfigTests.swift | test `validationFlagsKeysThatHaveNoEffect` étendu |
| AI-001 | `window close` non implémenté sortait en 0 | Sources/RoadieDaemon/CLICommandRouter.swift ; Tests/RoadieDaemonTests/CLICommandRouterTests.swift | test `unimplementedCommandsExitOne` |
| TEST-001 | Règle d'ambiguïté du rattachement non testée (FR-006) | Tests/RoadieDaemonTests/PersistentStageStateTests.swift | mutation de la règle -> test rouge |
| TEST-002 | Expiration des refus de taille non testée (FR-004) | Tests/RoadieDaemonTests/LayoutMaintainerTests.swift | mutation de l'expiration -> test rouge |

## Contre-revue des corrections
Agent indépendant en lecture seule : 7/7 confirmées. Deux réserves retenues et traitées dans ce cycle (PERF-001 : pas de mise en cache d'une lecture échouée ; MIN-002 : champs morts `LegacyHeader.height/width` supprimés). Une réserve gardée comme finding résiduel LOW (double lecture non atomique du marqueur, cf. cycle-scoring). Une réserve réfutée (EventLog redirigé en test, EventLog.swift:75).

## Blocked
Aucun.

## Non traités (recommandations, voir cycle-scoring)
- Choix de conception : REL-001 (requête socket d'un client parti), REL-002 (mutate refusé affiché comme succès), OBS-001/OBS-002 (état illisible et socket absents de doctor/daemon-status), QUAL-001 (code de sortie déduit du texte).
- Scripts non testables par la suite : QUAL-002 (scripts/doctor), QUAL-006 (cleanup renomme un log ouvert), QUAL-007 (install : bootstrap puis kickstart -k).
- Refactors : QUAL-003 (switchDisplay x3), QUAL-004 (tick 352 lignes), QUAL-005/QUAL-011 (tolérances littérales FR-041), QUAL-009, QUAL-010, DUP-001, DUP-002, MIN-003.
- Code mort préexistant au diff : MIN-001 (ParkingSession*).

## Prochaine action
- Revue humaine des 7 corrections puis commit par l'orchestrateur appelant.
- Ouvrir une session pour les MEDIUM de conception (OBS-001/OBS-002/REL-002 forment un même lot « mode dégradé visible »).
