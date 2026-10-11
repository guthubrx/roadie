# Journal d'implémentation : Tiling réactif façon yabai

## Métadonnées

- **Spec** : 017-reactive-tiling
- **Branche** : `017-reactive-tiling` (créée depuis `016-roadie-stabilization`, non fusionnée)
- **Démarré** : 2026-10-11 02:16 (CEST)
- **Terminé** : 2026-10-11 05:50 (CEST). Validation manuelle considérée résolue par décision utilisateur le 2026-10-11

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

Ce journal conserve les mesures techniques. Les chemins personnels, identifiants de fenêtres et de processus, nom de stage privé et empreinte du certificat sont retirés. Les dimensions sont conservées pour reproduire les défauts.

Installation le 2026-10-11 à 03:47 : `ROADIE_CODESIGN_IDENTITY="roadied-cert" make install && make stop && make restart`.

- `roadie doctor` : `status=ok`, `accessibilityTrusted=true`.
- **Migration** : `state_migrated` avec `stages=52` et la sauvegarde `~/.roadies/stages.json.pre-017`. Plus aucune stage `mutableBsp`. Les stages et leurs fenêtres sont conservées : un stage conserve 9 fenêtres vivantes, les membres périmés ont été purgés.
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

## Correction de validation : installation et redémarrage (T226, T227)

Le 2026-10-11, le tiling et le navrail disparaissent après une installation et un redémarrage. Une instance ouverte comme application reste vivante hors launchd. Son identifiant de processus est retiré de ce journal public. Elle conserve le verrou, mais son pidfile a disparu. Le service a déjà tenté 43 démarrages et échoue avec `already running`.

Cause vérifiée : l’ouverture de Roadie.app sans arguments lance le daemon. La commande visible dans `ps` ne contient pas `run --yes`. L’ancien script d’arrêt exigeait ces arguments. Il ignorait donc cette instance et supprimait tout de même son pidfile.

- **T226** : l’arrêt vérifie le chemin de l’exécutable. Il récupère le PID dans le statut lorsque le pidfile manque. Il attend la fin du daemon et conserve tout PID vivant non reconnu. `make restart` arrête l’ancienne instance, puis recharge le service. Le démarrage exige un PID vivant identique dans launchd et le pidfile.
- **T227** : l’installation reprend le certificat existant. Elle conserve son empreinte exacte lorsque la signature la fournit. Une identité absente bloque le remplacement, même si un autre certificat porte le même nom. Le choix explicite garde sa priorité.
- **Tests** : 26 tests scripts passent, dont 19 nouveaux tests de cycle de vie. Les commandes système et les signaux sont simulés. La syntaxe Bash et `git diff --check` passent. La relecture a vérifié les deux corrections de certificat et de confirmation du démarrage.
- **Essai réel** : `env -u ROADIE_CODESIGN_IDENTITY make install`, puis `make restart` réussissent. Les deux produits Swift compilent en release. `codesign --verify --strict` passe. L’exigence de signature conserve le certificat existant (empreinte retirée).
- **Résultat** : le PID correspond à launchd, au pidfile et au statut. Accessibilité et Enregistrement d’écran sont autorisés. Les 7 fenêtres sont gérées. Le navrail réserve 150 pixels. `roadie query health` ne contient que des contrôles `ok`.
- **Validation utilisateur** : l’utilisateur confirme que le tiling et le navrail sont tous deux revenus.

Pour contrôler le daemon, utiliser `roadie query health`. Les commandes locales `doctor` et `daemon health` peuvent relever des fenêtres avec les permissions propres au terminal. Leur relevé local vide ne prouve pas que le daemon n’a aucune fenêtre.

## Correction de validation : échange asymétrique (T228)

Le dépôt du terminal source sur l’application cible est retrouvé le 2026-10-11. L’échange donne d’abord la grande case au terminal. La réparation du minimum de T3 conserve ensuite le ratio imbriqué de 0,5. Elle exige une colonne droite de 1690 pixels et réduit le terminal à 190 pixels. Le calcul reproduit exactement la frame de T3 dans le journal : `350,660 840x612`.

- **Correction** : calculer les besoins des sous-arbres, choisir l’ancêtre faisable le plus proche et ajuster les splits nécessaires du chemin. Les orientations, les autres ratios et les feuilles absentes restent conservés. Le contrôle final utilise le placement réel, avec ses marges et arrondis.
- **Résultat reproduit** : avec un minimum voisin de 120, le terminal garde `910x1234`, T3 reçoit `840x612` et sa voisine reçoit `120x612`.
- **Minima inconnus** : le maintainer fournit le côté minimal supposé existant de 120 pour les voisines sans minimum appris. Sans cette valeur, l’API brute peut demander 45 à une voisine qui refuse sous 120 ; le test montre alors une nouvelle passe et une stabilité non atteinte. Les placements ordinaires et la signature de l’API sont inchangés.
- **Preuves rouges** : le test du moteur et le test d’intégration échouent sur la largeur de 190 avec l’ancien calcul. La variante d’intégration avec un minimum voisin encore inconnu prouve aussi le besoin de fournir le côté minimal supposé.
- **Tests** : les 30 tests du moteur passent. La suite complète donne 781 tests verts dans 85 suites. Le test d’intégration vérifie les deux variantes, les frames réelles du plan corrigé, au plus deux écritures par fenêtre, une génération conservée, puis `layout_stable` et aucune réécriture ultérieure.
- **Vérification indépendante** : le calcul concorde avec l’énumération des coupes sur 12 613 cas. Aucun défaut bloquant n’est trouvé pour des dimensions utilisables. Un cas dégénéré avec des feuilles brutes de largeur nulle reste hors de cette validation.
- **Installation réelle** : `make install`, sans identité de signature explicite, puis `make restart` réussissent. Les deux produits compilent en release. La signature stricte passe et conserve le certificat existant. Le nouveau daemon répond avec tous les contrôles `ok`, dont l’accessibilité et la validité de la configuration.
- **Essai utilisateur du 2026-10-11** : deux fenêtres dans la stage 1. Le terminal source mesure 234 de large avant le dépôt. Le journal confirme un `swap`, puis un refus de l’application cible avec un minimum de `840x120`. La correction applique deux placements sans refus ni échec et atteint la stabilité en 340 ms, dans la même génération 23. Avec 1880 de largeur partageable, le calcul donne environ 1040 au terminal et 840 à T3 ; cet aspect proche de l’équilibre vient du minimum de T3. Un second échange réussit sans refus et se stabilise en 137 ms. Le scénario imbriqué à quatre fenêtres reste validé par les tests ; son résultat à 910 pixels n’est pas une mesure de cet essai à deux fenêtres.

## Corrections de validation : retour d’écran et aperçu entre écrans (T229, T230)

Le 2026-10-11, l’utilisateur rebranche un écran externe longtemps absent. Le journal montre le changement de topologie au retour de l’écran, puis neuf écritures à la fin de la garde. La bascule de stage sur l’externe juste après annonce deux membres, mais aucune fenêtre cible vivante ou visible. Le geste sur T3 ensuite n’a aucun aperçu reconnu ; un autre transfert plus tard est adopté après le relâchement. Les aperçus sur le même écran fonctionnent ensuite.

- **Masquage et topologie** : la reproduction reprend l’interne à `2048x1280`, puis l’interne à `1512x982` et l’externe à `(1512,-964,3840,2160)`. L’ancienne position de masquage `x=2047` tombe alors dans l’externe. Une preuve en mémoire garde l’identité, le cadre réellement observé et le début d’une éventuelle absence. Elle survit à l’invalidation du cache et à une courte absence AX. Un nouveau cadre ou une nouvelle identité la libère. La preuve d’une fenêtre absente expire après 45 s. Aucun ancien bord d’écran n’est deviné sans observation de cette fenêtre.
- **Écritures AX** : les cadres relus après une application en lot ou une écriture directe alimentent cette preuve avant toute invalidation. Le cas où une autre fenêtre du lot échoue est couvert. La normalisation d’une fenêtre solo utilise aussi cette preuve : une ancienne position ressemblant au plein écran externe ne remplace pas son cadre utile. Membres, pins et signets conservent ainsi leur dernière position visible.
- **Anciennes références** : le daemon mémorise les dates des observations réelles sans écrire l’état au repos. La première absence au retour d’un écran ne fabrique plus une date de présence. La carte d’un membre absent exige une observation récente réelle et garde sa grâce de 15 s. Un lecteur intercalé ne consomme pas cette information. Les stages, leurs noms, leurs arbres et la grâce de membership de 30 min restent conservés.
- **Mode du stage vide** : le snapshot restaure le mode actif même si `ensureDisplay` a déjà créé le stage 1 et si aucune fenêtre vivante ne passe dans la boucle. Un stage vide à arbre utilise donc le même chemin que les autres stages à arbre. Un stage `float` vide reste refusé pour le dépôt tilé.
- **Aperçu entre écrans** : le scope cible suit le pointeur. Au centre d’une fenêtre de l’autre écran, le dépôt insère à droite ; sur un bord, il suit ce bord. Sur le même scope, le centre reste un échange. Une copie locale affecte la source à la destination pour calculer les marges automatiques après transfert. Le contexte figé et l’état persisté restent inchangés pendant l’aperçu.
- **Projection vide** : une destination sans fenêtre vivante peut recevoir la source, même si l’arbre conserve des feuilles historiques. L’aperçu prépare la même insertion que le dépôt. Les feuilles absentes restent présentes dans l’arbre, mais ne reçoivent aucune écriture. L’annulation hors des fenêtres d’une projection non vide reste conservée.
- **Preuves rouges** : avant correction, les tests reproduisent l’absence de candidat entre écrans, le cadre sauvegardé à `x=2047`, les deux cartes historiques et leur fausse date de présence. La relecture ajoute deux cas rouges : masquage écrit puis cache invalidé avant hotplug, et masquage qui ressemble au plein écran de l’externe. Un test d’ordre détecte aussi le stage vide qui utilisait le mode `bsp` par défaut.
- **Tests** : 46 tests ciblés passent. La suite finale donne **796 tests verts dans 85 suites**. L’intégration vérifie zéro écriture pendant le geste, aperçu égal au placement final, une écriture par fenêtre attendue dans la génération du dépôt, puis `layout_stable` et aucune réécriture après 5 s. Le test du refus de `width` sur un stage vide reçoit une configuration et un état isolés ; son résultat ne dépend plus de la configuration de la machine.
- **Relecture** : les deux périmètres, masquage/références et aperçu/dépôt, ne présentent plus de défaut bloquant identifié. L’utilisateur considère les essais manuels résolus le 2026-10-11 ; aucun résultat détaillé par geste n’est consigné.
- **Installation réelle** : `env -u ROADIE_CODESIGN_IDENTITY make install`, puis `make restart` réussissent. La signature stricte conserve le certificat existant (empreinte retirée). Le daemon est vivant et tous les contrôles de `roadie query health` sont `ok`. Il relève les deux écrans attendus et 28 fenêtres. Le plan de démarrage du 2026-10-11 applique huit placements sans refus ni échec, en une écriture par fenêtre, puis atteint la stabilité en 300 ms.
