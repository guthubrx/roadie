# Journal d'implémentation : Tiling réactif façon yabai

## Métadonnées

- **Spec** : 017-reactive-tiling
- **Branche** : `017-reactive-tiling` (créée depuis `016-roadie-stabilization`, non fusionnée)
- **Démarré** : 2026-10-11 02:16 (CEST)
- **Terminé** : 2026-10-11 05:50 (CEST). Validation manuelle en attente

## Méthode

- Pipeline `/my.specify-all` : spec, plan (avec 3 recherches en parallèle), audit de réutilisation, contre-revue du plan par Codex en 2 rounds, tâches, analyse, implémentation en 3 vagues.
- Implémentation parallèle par lots à fichiers exclusifs : 4 lots en vague 1, 4 lots en vague 2. Agents Opus, sauf l'instrumentation en Sonnet. Chaque lot compile dans son propre répertoire de build.
- L'orchestrateur fait la jonction entre les vagues (constantes, interfaces provisoires), commite par lot, puis vérifie la suite complète après une recompilation à neuf.

## Progression par lot

| Lot | Tâches | Commit | Résultat |
|---|---|---|---|
| L1 Instrumentation | T010-T013 | `b34a092` | `tsMs`, `episodeId`, `EpisodeContext`, catalogue, outil de mesure enrichi. 5 tests |
| L2 Cache et migration | T020-T023 | `eb37b20` | Cache par signature `fstat` revalidée sous verrou, `mutate` sans écriture si inchangé, `migrateLegacyTreeModes` avec sauvegarde unique. 8 tests |
| L3 AX | T030-T035 | `4817b8c` | Écriture taille-position-taille, `AXEnhancedUserInterface` neutralisé, relecture unique, index AX réutilisé, `WrittenFrameRegistry`, événements déplacé et redimensionné, échos absorbés, `SpaceProbe`. 32 tests |
| L4 Arbre | T040-T045 | `503de6d` | Coupe selon la feuille, opérations avec exclusions, `correctingForMinimumSize`, `inferred`, alias de config. 21 tests et plus |
| Jonction | T050-T051 | `7c4189e` | Constantes, `PlacementGeneration`, stubs, `layout_stable` |
| L6 Ordonnanceur | T060-T064 | `751751c` | `TickScheduler`, filet à 2 s, notifications NSWorkspace, session de geste avec moniteurs locaux et globaux, glisser sans grâce en mode arbre. 21 tests |
| L9 Commandes | T090-T095 | `f51b6b5` | move, warp, resize, balance, toggle-split, glisser-déposer, navrail et bascules sur l'arbre en une application. Environ 526 lignes retirées |
| L8 Snapshot | T080-T084 | `5be449e` | L'arbre fait foi (plus d'intents sauf le zoom), feuilles gardées pendant la grâce, migration au démarrage, `applyTreeScope`, republication du snapshot. 13 tests |
| Docs | T102-T103 | `53ec924` | ADR 009 et 010, README, exemple de config, branchement de `noteWindowDestroyed` |
| L7 Maintainer | T070-T077 | `f77e0d8` | Passe unique en 5 étapes, rafales (A18), garde de bureau (A5, A19), classement des frames, budget par génération, tolérance unique. Environ 432 lignes mortes retirées. 20 tests et plus |
| Vague 3 | T100, T101, T104 | `2e37f68` | `MutableBSPLayoutStrategy` et la réparation d'ordre supprimés. Moins 513 lignes |

## Tests

- Avant la 017 : 627 tests. Après : **734 tests, tous verts** (recompilation à neuf, `./scripts/test`).
- Les tests propres à l'ancienne stratégie `mutableBsp`, où la géométrie observée faisait foi, ont été retirés avec leur raison : 7 dans `LayoutMaintainerTests`, 8 dans `LayoutPlannerTests`, 4 dans `DropPreviewEngineTests` (remplacés par 5 tests arbre), 1 dans `SnapshotServiceTests`. Les autres ont été réécrits pour l'arbre ou passés en `bsp`.

## Installation et mesures réelles (T105)

Installation le 2026-10-11 à 03:47 : `ROADIE_CODESIGN_IDENTITY="roadied-cert" make install && make stop && make restart`.

- `roadie doctor` : `status=ok`, `accessibilityTrusted=true`.
- **Migration** : `state_migrated` avec `stages=52` et la sauvegarde `~/.roadies/stages.json.pre-017`. Plus aucune stage `mutableBsp`. Les stages et leurs fenêtres sont conservées : Perso a 9 fenêtres vivantes, les membres périmés ont été purgés.
- **Repos (SC-003)** : 60 s sans interaction, **0 placement**.
- **Durée d'une passe** (`live_tick.durationMs`) : médiane 5,3 ms, maximum 7 ms. Avant : médiane 35,6 ms.
- **Latence avant traitement** (`live_tick.latencyMs`) : médiane 68,8 ms pour un regroupement visé de 15 ms. **À expliquer** (thread principal occupé ?), voir la contre-revue de l'implémentation.

| Indicateur | Avant (journal complet) | Après |
|---|---|---|
| Placement au repos (60 s) | une passe à chaque dérive de géométrie | 0 |
| Durée d'une passe, médiane | 35,6 ms | 5,3 ms |
| Temps jusqu'à stabilité, médiane / p90 | 1 s / 6 s | 0,39 s / 2,9 s (6 épisodes réels, 04:27-05:50) |
| Passes par épisode, médiane / p90 | 1 / 6 | 1 / 2 |
| Écritures max par fenêtre | non mesuré | 2 (aucun dépassement du budget) |
| Latence avant passe, médiane | 15,9 ms (16 % des ticks) | 72,7 ms (attente sur la file principale, `dueLagMs` ≈ 60 ms) |

Lecture : l'échantillon réel est petit (6 épisodes). Le p90 de 2,9 s vient d'un épisode avec une garde `member_return` fermée par `timeout` (1 642 ms) : la sonde lisait un bureau plein écran (type 4) sur l'écran. SC-001 (p90 < 150 ms) n'est donc pas encore démontré sur l'usage réel. À confirmer par la campagne de `quickstart.md`.

## Ce qui reste à valider à la main

Voir `quickstart.md` : scénarios 1 à 9, campagne multi-applications et application lente.

Points non vérifiés par les tests automatiques :
- sonde de bureau réelle pendant une sortie de plein écran ;
- gestes à la vraie souris ;
- effet de la neutralisation d'`AXEnhancedUserInterface` sur T3 Code et les applications Electron ;
- écran à arbre à côté d'un écran `bsp`.

## Écarts assumés

- `revertedAppliedFrames` et `lastObservedFrames` restent dans le maintainer, pour `bsp` et `masterStack` seulement (A3).
- `BSPTree.inserting(_:nextTo:side:containerIsWide:)`, `removing` et `swapping` sont conservés : le dépôt impose le sens de coupe par le bord visé.
- `window desktop N`, `window display N` et `toggle native-fullscreen` gardent l'attente globale de commande. L'insertion dans l'arbre cible passe par la réconciliation.
- Bilan de lignes de la 017 dans `Sources` : 4107 ajoutées, 2567 supprimées.

## Audit de code v14 (2026-10-11)

Session : `audits/2026-10-11/session-2026-10-11-017-reactive-tiling-01/` (mode fix, 1 cycle et un cycle de scoring). Aucun CRITICAL ni HIGH après le contre-audit. Quatre corrections MEDIUM, non commitées. Chacune est prouvée par un test rouge sans la correction :

- **REL-002** : une relecture de refus qui ne tranche pas est retentée `spaceGuardPoll` plus tard. Avant, l'échéance passée relançait une passe au plancher de 15 ms jusqu'à `echoWindow`. Fichier : `LayoutMaintainer.swift`. Test : `inconclusiveRefusalReadIsDelayed`.
- **QUAL-101** : `layout <verbe>` ne relève plus les fenêtres avant le verbe. Seuls `plan` et `apply` relèvent. Fichier : `CLICommandRouter.swift`. Test : `layoutVerbDoesNotScanBeforeItsCommand`.
- **TEST-003** (avec ARCH-101 en partie) : `applyCommandPlacement` publie au centre du service et lit son horloge. Avant, il publiait à `TreeScopeApplicationCenter.shared` et lisait `Date()`. Fichiers : `LayoutCommandService.swift`, `DaemonSnapshot.swift`. Test : `treeStageSwitchPublishesItsApplicationToTheServiceCenter`.
- **MIN-001** : `commandLayoutIntentNeedsApply` est supprimée (FR-018), car elle n'avait plus d'appelant. Cela retire 25 lignes.

Tests : `./scripts/test` donne 773 tests verts (770 avant). `python3 -I -B -m unittest discover scripts/tests` donne 7 tests verts.
