# Rapport des cycles de correction - audit v14 SPEC-017

## Résumé
- Cycles : 1 cycle fix (`cycle-1/`) et 1 cycle de scoring en lecture seule (`cycle-scoring/`).
- CRITICAL/HIGH à corriger : 0. Les 2 HIGH (QUAL-001, TEST-001) ont été réfutés par le contre-audit et rétrogradés en MEDIUM.
- Sélection (consigne appelant) : MEDIUM simples et sûrs, confirmés par un contre-audit volontaire.
- Findings sélectionnés : 4. Corrigés : 4. Bloqués : 0. Disjoncteur non déclenché (aucun échec de correction).
- Commits : aucun (AUTO_COMMIT=false, imposé par l'orchestrateur appelant, qui commitera).
- Tests : `./scripts/test --scratch-path /tmp/roadie-build-audit` donne **773 tests / 85 suites verts** (770 avant, +3). `python3 -I -B -m unittest discover scripts/tests` donne 7 tests OK. Aucun `__pycache__` créé.

## Fixed (non commité)
| Finding (cycle-1) | Titre | Fichiers | Vérification |
|---|---|---|---|
| REL-002 | Une relecture de refus non concluante relançait une passe au plancher de 15 ms jusqu'à `echoWindow` | `Sources/RoadieDaemon/LayoutMaintainer.swift` ; `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift` | `inconclusiveRefusalReadIsDelayed`, rouge sans la correction (échéance déjà passée) |
| QUAL-101 | `layout <verbe>` relevait toutes les fenêtres et calculait un plan avant le verbe : 2 relevés par raccourci | `Sources/RoadieDaemon/CLICommandRouter.swift` ; `Tests/RoadieDaemonTests/CLICommandRouterTests.swift` | `layoutVerbDoesNotScanBeforeItsCommand`, rouge sans la correction (2 relevés contre 1) |
| TEST-003 (+ ARCH-101 en partie) | `applyCommandPlacement` publiait à `TreeScopeApplicationCenter.shared` et lisait `Date()`, au lieu du centre et de l'horloge du service (T219 non testé) | `Sources/RoadieDaemon/LayoutCommandService.swift` ; `Sources/RoadieDaemon/DaemonSnapshot.swift` ; `Tests/RoadieDaemonTests/CommandSinglePlanTests.swift` | `treeStageSwitchPublishesItsApplicationToTheServiceCenter`, rouge sans la correction (0 publication) |
| MIN-001 | `commandLayoutIntentNeedsApply` sans appelant (FR-018) | `Sources/RoadieDaemon/DaemonSnapshot.swift` | `rg` sans occurrence ; build et suite verts (25 lignes retirées) |

Journal de la spec : `specs/017-reactive-tiling/implementation.md`, section « Audit de code v14 ».

## Contre-revue des corrections
Un agent indépendant, en lecture seule, a confirmé les 4 corrections. Il a vérifié les 3 tests rouges dans une copie séparée de HEAD, puis la suite complète (773 verts).
- **Réserves retenues et appliquées** :
  - variable `confirmed` redondante dans `confirmPendingRefusals` (REL-002) ;
  - commentaire de `deadlines()` complété ;
  - commentaire de `CLICommandRouter` corrigé (les verbes ne passent pas tous par `activeContext`).
- **Défaut antérieur retenu** : finding résiduel **REL-011** (LOW) du cycle-scoring. `confirmPendingRefusals` n'a pas de borne `echoWindow`.

## Blocked
Aucun.

## Non traités (recommandations, voir cycle-scoring)
- **Infrastructure de test** : TEST-001 (défauts `.shared` jamais exercés), TEST-002 et TEST-005 (génération isolable par test, `@TaskLocal` sur une trentaine de sites), TEST-004 (règle de regroupement AX dans `main.swift`, cible non importable).
- **Refactors** : QUAL-001 (`tick`, 240 lignes), ARCH-001 (`LayoutMaintainer`, 3446 lignes), ARCH-002 et ARCH-003 (choix de dépendances selon `isRunningTests`, budget compté à 3 endroits), QUAL-004 (`startTilerComponent`), QUAL-102 (`switchDisplay`), DUP-001 et DUP-002.
- **Conception** : REL-004 (filtre et cadence des changements externes), QUAL-003 (`axWrites` estimé et non mesuré).
- **Documentation** : MIN-002 (bilan +2003 lignes nettes contre la « suppression nette » du plan, non arbitré).
- **Rétrogradés en LOW par le contre-audit, non corrigés** :
  - REL-001 : la remise d'`AXEnhancedUserInterface` est voulue ; il manque seulement la trace promise par `plan.md:182`.
  - REL-003 : le déclenchement n'est pas prouvé. Il faut d'abord observer (Article VIII).
  - QUAL-002, ARCH-102 et TEST-006.

## Prochaine action
- Revue humaine des 4 corrections, puis commit par l'orchestrateur appelant.
- Ouvrir un lot « câblage testable » qui regroupe TEST-001, TEST-002, TEST-005, ARCH-002, ARCH-003 et TEST-004. Ces findings ont la même cause : les dépendances `.shared` sont choisies selon `isRunningTests`, et la génération est globale.
