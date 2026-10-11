# Audit de Code - roadie, SPEC-017 (tiling réactif)

**Date** : 2026-10-11
**Mode** : fix (1 cycle et 1 cycle de scoring en lecture seule) | grid : pre-merge | scope_mode : diff (27cb244..HEAD, 61 fichiers dont 1 supprimé)
**Durée** : environ 53 min
**Score global** : A- (87,9/100, moyenne pondérée des domaines applicables)
**Coverage** : 100 % du périmètre diff (mode LIGHT, pas d'échantillonnage)
**Release bloquée** : non (0 CRITICAL, 0 HIGH)
**Corrections** : 4 appliquées dans l'arbre de travail, **non commitées** (consigne de l'orchestrateur appelant)

## Tendance (vs session précédente du même scope)

C'est la première session pour ce scope (SPEC-017). Pour comparaison, la session précédente du dépôt (`audits/2026-10-10/session-2026-10-10-016-roadie-stabilization-01`, SPEC-016, branche de base) avait obtenu A- (87,3).

| Domaine | Cycle-1 (avant corrections) | Cycle-scoring (après) | Delta findings |
|---------|-----------------------------|-----------------------|----------------|
| Global  | A- (86,6) | A- (87,9) | -4 corrigés, +1 résiduel (REL-011, issu de la contre-revue) |
| Fiabilité | A (90) | A (92) | REL-002 corrigé ; REL-011 ajouté (LOW) |
| Tests | B (76) | B (79) | TEST-003 corrigé |
| Qualité | B (75) | B (78) | QUAL-101 corrigé |
| Minimalisme | A- (87) | A (90) | MIN-001 corrigé (25 lignes mortes retirées) |
| Autres domaines | inchangés | inchangés | - |

Les notes par domaine sont calculées sur les 75 findings dédoublonnés, avant la troncature à 50. Sinon, les domaines dont tous les LOW sont tronqués seraient flattés : l'hygiène IA, par exemple, serait notée 100 au lieu de 96.

## Résumé exécutif

| Domaine        | Note | CRIT | HIGH | MED | LOW |
|----------------|------|------|------|-----|-----|
| Fiabilité      | A    | 0    | 0    | 1   | 5   |
| Observabilité  | A    | 0    | 0    | 0   | 4   |
| Tests          | B    | 0    | 0    | 4   | 9   |
| Complexité     | A    | 0    | 0    | 0   | 10  |
| Qualité        | B    | 0    | 0    | 4   | 10  |
| Architecture   | A-   | 0    | 0    | 3   | 5   |
| Hygiène IA     | A    | 0    | 0    | 0   | 4   |
| Duplication    | A-   | 0    | 0    | 2   | 6   |
| Minimalisme    | A    | 0    | 0    | 1   | 7   |
| Sécurité, supply chain, performance, UX | N/A | - | - | - | - |

Total : 75 findings (15 MEDIUM, 60 LOW). `cycle-scoring/aggregated-findings.json` retient les 50 premiers (15 MEDIUM, 35 LOW). Les 25 LOW tronqués sont listés dans `execution_metrics.warnings` (règle d'or 19).

Les modules 03 (sécurité) et 08 (performance) ne font pas partie de la grille pre-merge. La surface (socket local 0600, lecture privée SkyLight avec repli public) est décrite dans le threat model de `01_Decouverte.md`.

**Aucun finding critique.** Les 5 points à traiter en premier (MEDIUM) :
1. **REL-004** (`Sources/roadied/main.swift:406`) : chaque déplacement externe de n'importe quelle fenêtre déclenche une passe complète. Il n'y a ni filtre sur les fenêtres gérées ni cadence minimale.
2. **TEST-001, TEST-002, TEST-005 et ARCH-002** (même cause) : le câblage de production n'est presque jamais exercé. Le maintainer choisit 5 dépendances selon `TestEnvironment.isRunningTests` (`LayoutMaintainer.swift:145`). La génération globale `.shared` rend les tests de T223 non fiables en exécution parallèle (`CommandSinglePlanTests.swift:69`). 3 des 5 commandes de T223 n'ont pas de test.
3. **ARCH-003** (`LayoutMaintainer.swift:889`) : le budget d'écriture FR-005 est compté à trois endroits et fusionné par `max()`. Une partie de ce code de production compense le câblage des tests.
4. **QUAL-003** (`LayoutMaintainer.swift:1413`) : `axWrites` de `layout_apply` vaut `items × 3`, une estimation et non une mesure. Pourtant, l'outil de mesure (FR-016) l'additionne comme une mesure.
5. **TEST-004 et QUAL-004** (`main.swift:348-406`) : la règle de regroupement des notifications AX et la règle de blocage du tick sont dans la cible exécutable. Aucun test ne peut les atteindre.

**Dette technique** : modérée. Elle se concentre dans `LayoutMaintainer.swift`, qui fait 3 446 lignes avec 56 propriétés d'état. Sa fonction `tick` fait 240 lignes, pour une complexité cyclomatique de 23.

**Hotspots** (taille x churn du diff) :
1. `Sources/RoadieDaemon/LayoutMaintainer.swift` (3 449 lignes, +1 583/-1 240 dans le diff)
2. `Sources/RoadieDaemon/DaemonSnapshot.swift` (2 186 lignes, +439/-217)
3. `Sources/RoadieTiler/BSPTree.swift` (659 lignes, +475/-119)

## Findings par sévérité (cycle-scoring)

### CRITICAL (0) / HIGH (0)
Le cycle-1 contenait 2 HIGH. Le contre-audit (Phase 2bis, agents séparés) les a **réfutés** et rétrogradés :
- **QUAL-001** : SwiftLint mesure une complexité cyclomatique de 23 à `LayoutMaintainer.swift:170`, sous le seuil HIGH de 25. Le précédent de la SPEC-016 notait la même fonction en MEDIUM, à 352 lignes.
- **TEST-001** : les valeurs par défaut `.shared` sont écrites en dur, et le comportement partagé est couvert par `BudgetWiring` (`LayoutMaintainerTests.swift:2804-2810`). Le finding passe en MEDIUM, exploitabilité THEORETICAL.

### MEDIUM (15)
- **Câblage et tests** : TEST-001, TEST-002, TEST-005, ARCH-002 (dépendances choisies selon l'environnement de test, génération globale). TEST-004 et QUAL-004 (règles intestables dans `main.swift`).
- **Fiabilité** : REL-004 (passe à chaque changement externe, sans filtre).
- **Mesure** : QUAL-003 (`axWrites` estimé).
- **Structure** :
  - QUAL-001 (`tick`, 240 lignes) ;
  - ARCH-001 (classe de 3 446 lignes) ;
  - ARCH-003 (budget compté à 3 endroits) ;
  - QUAL-102 (`switchDisplay`, 322 lignes, préexistant et touché par la 017).
- **Duplication** : DUP-001 (plan « masquer et restaurer » recopié dans 5 commandes), DUP-002 (`assignActiveWindow` et `assign`, avec une dérive déjà présente).
- **Minimalisme** : MIN-002 (+2 003 lignes nettes dans `Sources`, contre la « suppression nette » annoncée par `plan.md:32`, non arbitré).

### LOW (60, dont 35 dans le JSON)
Le détail est dans `cycle-scoring/aggregated-findings.json`. On y trouve notamment :
- REL-011 : résiduel de la contre-revue ;
- REL-001 et REL-003 : rétrogradés par le contre-audit ;
- 10 constats de complexité à n borné (PERF-001 à PERF-010) ;
- TEST-007 : les tests Python de l'outil de mesure ne sont lancés par aucune commande du dépôt ;
- TEST-010 : un test tautologique.

## Détail des findings

Le détail complet (extrait, remédiation, vérification, empreinte) est dans `cycle-scoring/aggregated-findings.json`. L'état avant corrections et les statuts `fixed` sont dans `cycle-1/aggregated-findings.json`. Les journaux sont `cycles.log` et `fix-report.md`.

## Corrections appliquées (cycle-1, non commitées)

| Finding cycle-1 | Correction | Fichiers | Preuve |
|---|---|---|---|
| REL-002 | Une relecture de refus qui ne tranche pas est retentée `spaceGuardPoll` plus tard. Avant, l'échéance passée relançait une passe au plancher de 15 ms jusqu'à `echoWindow`. | `Sources/RoadieDaemon/LayoutMaintainer.swift` | test `inconclusiveRefusalReadIsDelayed`, rouge sans correction |
| QUAL-101 | `layout <verbe>` ne relève plus les fenêtres avant le verbe : 1 relevé par raccourci au lieu de 2. | `Sources/RoadieDaemon/CLICommandRouter.swift` | test `layoutVerbDoesNotScanBeforeItsCommand`, rouge sans correction |
| TEST-003 | `applyCommandPlacement` publie au centre du service et lit son horloge. Avant, il publiait à `.shared` et lisait `Date()`. Le comportement en production est identique. | `Sources/RoadieDaemon/LayoutCommandService.swift`, `DaemonSnapshot.swift` | test `treeStageSwitchPublishesItsApplicationToTheServiceCenter`, rouge sans correction |
| MIN-001 | Suppression de `commandLayoutIntentNeedsApply`, sans appelant (FR-018). | `Sources/RoadieDaemon/DaemonSnapshot.swift` | `rg` sans occurrence, suite verte |

**Batterie de tests** : `./scripts/test --scratch-path /tmp/roadie-build-audit` donne **773 tests / 85 suites verts** (770 avant). `python3 -I -B -m unittest discover scripts/tests` donne 7 tests OK, sans `__pycache__`.

**Contre-revue indépendante des corrections** :
- 4 corrections sur 4 confirmées ; les 3 tests rouges sur HEAD ont été vérifiés dans une copie séparée ;
- 2 réserves mineures appliquées ;
- 1 défaut antérieur retenu comme finding résiduel REL-011.

## Quick Wins

| ID | Description | Effort | Impact | Fichier |
|----|-------------|--------|--------|---------|
| REL-011 | Borner `confirmPendingRefusals` à `echoWindow`, comme `deadlines()` | XS | LOW | `Sources/RoadieDaemon/LayoutMaintainer.swift:1008` |
| TEST-007 | Lancer `scripts/tests` depuis `./scripts/test` (T203 annonçait ce lancement) | XS | LOW | `scripts/test:11` |
| TEST-010 | Remplacer l'assertion toujours vraie de la sonde réelle | XS | LOW | `Tests/RoadieAXTests/ReactiveTilingAXTests.swift:499` |
| ARCH-102 | Rendre `generation:` obligatoire sur `apply` et `setFrame` (0 appelant de production à adapter) | S | LOW | `Sources/RoadieDaemon/DaemonSnapshot.swift:1683` |
| DUP-002 | Faire déléguer `assignActiveWindow` à `assign` (dérive du garde « déjà sur ce bureau ») | S | MEDIUM | `Sources/RoadieDaemon/DesktopCommands.swift:124` |

## Dépendances vulnérables

Non évalué (module 03 hors grille). Une seule dépendance tierce : TOMLKit. Les symboles privés SkyLight sont résolus par `dlsym`, en lecture seule, avec un repli public (ADR 010).

## Complexité algorithmique (Article XVIII)

Le module 04 a vérifié le périmètre sur tous les fichiers `Sources` du diff et sur l'outil de mesure. Il n'a trouvé aucun anti-pattern HIGH ou CRITICAL. Les 10 constats LOW portent sur des valeurs de n bornées (moins de 50 à 100 fenêtres). Deux annotations O() sont inexactes : `SpatialBSPLayoutStrategy.swift:28` et `BSPTree.swift:60`. Le registre des frames écrites est balayé à chaque passe (`WrittenFrameRegistry.swift:102`). Une écriture AX est isolée par voisine masquée (`WindowCommands.swift:578`).

## Minimalisme & Frugalité (axe OBLIGATOIRE - Article XIX constitution)

Les checklists du module 12 ont été exécutées sur tout le diff `Sources` et sur l'outil de mesure. Le travail de la vague 3 tient : `MutableBSPLayoutStrategy` (-233 lignes), `TickDuration`, `pendingLiveTick` et `revertedAppliedFrames` hors modes sans arbre ont disparu. Chaque constante de `LayoutTolerance` a un lecteur.

Résidus :
- **Surface de production servie aux seuls tests** : surcharges `setFrame`/`setFrames` sans génération (MIN-003), relais statiques d'`EpisodeContext` (MIN-004), `applyTreeScope(episodeID:)` (MIN-005), `GestureSession.endedAt` (MIN-006), `isObsolete` (MIN-007).
- **Alias `mutableBsp` écrit deux fois** (QUAL-008) et clause morte (AI-001).
- **`intervalSeconds`** toujours à 0,5 (MIN-010).
- **Événements `mutable_bsp_*`** encore traités par l'outil de mesure (MIN-013).
- **Bilan net non arbitré** (MIN-002).

Pendant ce cycle, `commandLayoutIntentNeedsApply` a été retirée (25 lignes).

Potentiel minimalisme : ~86 lignes suppressibles à comportement constant. C'est l'estimation du module 12 (~112 lignes), moins les 25 lignes retirées et 1 variable redondante évitée. Cela représente environ 1,8 % des 4 790 lignes ajoutées dans `Sources`. Le sujet principal est le volume net (MIN-002), pas ces résidus.

## Vertus LLM & Responsabilité Future (axe OBLIGATOIRE - Article XX constitution)

- **Charge cognitive future** : en hausse à court terme. La logique est plus juste (l'arbre fait foi, passe unique, budget par génération), mais elle reste concentrée dans `LayoutMaintainer.swift`. Ce fichier mêle le moteur à arbre et la chaîne historique des modes `bsp` et `masterStack` (ARCH-001, écart assumé A3). Ses commentaires renvoient à 94 codes A, R et T définis seulement dans `specs/` (AI-003, `LayoutMaintainer.swift:1324`).
- **Volume justifié** : en partie. Les suppressions sont réelles (MutableBSP, réparation d'ordre, environ 1 000 lignes mortes), mais le bilan donne +2 003 lignes nettes. La spec attendait une suppression nette, et l'écart n'est pas écrit (MIN-002).
- **Abstractions** : elles servent un besoin réel. Exemples : `WrittenFrameRegistry` (registre court, classement pur et testable), `PlacementGeneration`, `TickScheduler` (dépendances injectées), `CommandPlacement` (plan unique de T212). Il y a trois réserves :
  - choix des dépendances selon `isRunningTests` dans un constructeur de production (ARCH-002) ;
  - budget compté à trois endroits (ARCH-003) ;
  - suivi d'`applyTreeScope` recopié dans `applyCommandPlacement`, avec le commentaire « contournement local » (ARCH-101).
- **Code assumable** : oui pour l'intention. Les complexités sont annotées, les choix sont reliés à des amendements, et les refus sont explicites et testés. Deux zones sont à expliquer : `axWrites`, estimé mais présenté comme mesuré (QUAL-003), et `intervalSeconds`, figé (MIN-010).
- **Patterns LLM détectés** :
  - surface publique réservée aux tests (`AXWindowEventObserver.swift:81`, `EventLog.swift:99`) ;
  - test tautologique (`ReactiveTilingAXTests.swift:499`) ;
  - test qui compare à un littéral (`PowerUserLayoutCommandTests.swift:159`) ;
  - copies non factorisées (`WindowBookmarkCommands.swift:110`, `DesktopCommands.swift:124`).

  Aucun empilement de couches sans règle n'a été trouvé. La réécriture de `LayoutMaintainer.swift` est reliée aux tâches T070-T077.
- **Corrections de cet audit** : elles sont ciblées. Le diff compte 139 lignes ajoutées et 40 retirées sur 8 fichiers, dont 111 lignes de tests et le journal. Chaque correction est prouvée par un test rouge sans elle (ou par `rg` pour MIN-001), puis relue par un agent indépendant.

## Findings supprimés par la baseline

Aucun : `audits/baseline.json` est absent (baseline vide).

## Points positifs

- `Sources/RoadieDaemon/JSONPersistence.swift:194` : `readSigned` lit les octets depuis le descripteur qui a servi au `fstat`. La signature et les octets restent cohérents même si un renommage remplace le fichier (FR-011, A7).
- `Sources/RoadieDaemon/StageStore.swift:205` : la migration `mutableBsp` tient en une transaction. Elle garde l'ordre des membres et sauvegarde une seule fois les octets d'origine en `.pre-017` (FR-013).
- `Sources/RoadieDaemon/TickScheduler.swift:51-79, 160` : toutes les dépendances sont injectées et il n'y a qu'un minuteur. Le plancher de 15 ms s'applique seulement à l'armement, et une passe bloquée ne réarme pas le minuteur.
- `Sources/RoadieAX/WrittenFrameRegistry.swift:28-125` : registre court, avec un verrou unique et une complexité annotée. Le classement écho, réponse ou externe est pur et testable.
- **Tests** : pas de `sleep` ni de délai réel dans les tests du lot 017, et les horloges sont manuelles. T204 est corrigé : `expectOneWrite` et `expectFinalTreeFrames` exigent exactement une écriture. Le budget A13 est testé au point commun d'écriture. La duplication des `Sources` est faible : 1,10 % selon jscpd.

## Roadmap de remédiation

1. **Immédiat (< 1 sem)** : aucun bloquant.
2. **Court terme (< 1 mois)** :
   - lot « câblage testable » : TEST-002, TEST-005 (génération isolable), TEST-006 ;
   - QUAL-003 (`axWrites` mesuré ou renommé) ;
   - REL-011, TEST-007.
3. **Moyen terme (< 3 mois)** :
   - REL-004 (filtre et cadence des changements externes) ;
   - ARCH-002 et ARCH-003 (registre unique, fabrique de test) ;
   - TEST-001 et TEST-004 (règles de `main.swift` extraites dans `RoadieDaemon`) ;
   - QUAL-004, DUP-001, DUP-002, ARCH-101.
4. **Long terme** :
   - découpage de `tick` (QUAL-001), de `LayoutMaintainer` (ARCH-001) et de `switchDisplay` (QUAL-102) ;
   - arbitrage du bilan de lignes (MIN-002).

## Non vérifié (mémoire négative)

- **Comportement sur le bureau réel** : notifications AX, sonde SkyLight pendant une sortie de plein écran, gestes à la souris, `AXEnhancedUserInterface` sur Electron. Le daemon n'a pas été lancé (consigne). La tâche T106 et `quickstart.md` restent ouverts.
- **Modules 03 (sécurité) et 08 (performance)** : hors grille.
- **Lecture partielle** : `LayoutMaintainer.swift`, `DaemonSnapshot.swift` et `SnapshotServiceTests.swift` ont été lus par fonctions ciblées et par recensement de symboles, pas en entier ligne à ligne. Les tests historiques de `LayoutMaintainerTests` (lignes 1 à 2 795) ont été lus par extraits.
- **REL-003** : il n'a pas été vérifié sur machine si une notification de destruction peut venir d'un élément qui répond encore.
