# Tasks: Tiling réactif façon yabai

**Input**: Design documents from `specs/017-reactive-tiling/`
**Prerequisites**: plan.md, spec.md, research.md (R1 à R15, puis amendements A1 à A20, les plus récents priment), data-model.md, contracts/, reuse-audit.md, adversarial-review-codex.md
**Organisation** : les tâches sont regroupées par lot. Chaque lot est le propriétaire unique de ses fichiers (voir plan.md). Chaque tâche porte l'étiquette de sa user story. `[P]` signifie parallélisable avec les autres lots de la même vague.
**Vérification commune** : `./scripts/with-xcode swift build` puis `./scripts/test` après chaque lot ; un commit par lot.

## Phase 1 : Setup

- [x] T001 Écrire `specs/017-reactive-tiling/agent-brief.md` : règles de travail parallèle, lecture obligatoire, rapport attendu.
- [x] T002 Commiter `scripts/measure-layout-reactivity` et consigner les chiffres « avant » dans `research.md`.
- [x] T003 Écrire `specs/017-reactive-tiling/adversarial-review-codex.md` (round 1 du plan) et propager les amendements dans spec, plan, data-model, contrat, quickstart.

## Phase 2 : Vague 1

### Lot L1 - Instrumentation (Sonnet) [US5]

- [x] T010 [P] [US5] Ajouter `tsMs` et `episodeId` à `RoadieEvent` (`Sources/RoadieDaemon/EventLog.swift`), et `tsMs` à l'enveloppe (`Sources/RoadieCore/AutomationEvent.swift`). Ajouter un contexte d'épisode global au processus, protégé par verrou : `EpisodeContext.begin(cause:)`, `current`, `continue()`. Un épisode reste ouvert à travers ses échos et ses échéances, et se ferme après 1 s sans cause externe nouvelle (A12). Les champs sont optionnels, et les anciennes lignes se décodent toujours.
- [x] T011 [P] [US5] Déclarer dans `Sources/RoadieCore/AutomationEventCatalog.swift` les types du contrat (`layout_echo_ignored`, `layout_app_response_accepted`, `layout_external_change_reverted`, `layout_manual_gesture`, `space_transition_guard`, `state_migrated`). Marquer les `mutable_bsp_*` comme obsolètes.
- [x] T012 [P] [US5] Adapter `scripts/measure-layout-reactivity` :
  - utiliser `tsMs` et `episodeId` quand ils sont présents ;
  - distinguer fin d'écriture, stabilité observée et fin de garde de bureau ;
  - compter les écritures par fenêtre, `scans` et `axWrites` ;
  - garder le découpage actuel pour les anciennes lignes.
- [x] T013 [US5] Tests EventLog :
  - une ancienne ligne sans les nouveaux champs se décode ;
  - `tsMs` est cohérent avec `timestamp` ;
  - `episodeId` est posé par le contexte et reste stable à travers `continue()`.

### Lot L2 - Cache de l'état et migration (Opus) [US1, US3]

- [x] T020 [P] [US1] Implémenter dans `Sources/RoadieDaemon/JSONPersistence.swift` le contrat A7 : signature `fstat` sur le descripteur ouvert (mtime ns, taille, inode), octets lus depuis ce même descripteur, revalidation après acquisition du verrou. Après un `mutate` qui écrit, publier la valeur et la signature avec le verrou encore tenu. Aucun encodage ni écriture si la valeur est égale. Réutiliser ou étendre `fileModificationStamp`. `.missing`, `.corrupt` et le refus d'écriture restent inchangés.
- [x] T021 [P] [US1] Brancher `StageStore.state()`, `LayoutIntentStore` et `LayoutCommandActivity` sur ce cache (`StageStore.swift`, `LayoutIntentStore.swift`, `LayoutCommandActivity.swift`).
- [x] T022 [P] [US3] Ajouter `StageStore.migrateLegacyTreeModes(infer:container:)` (A8), sous un seul verrou :
  1. lire les octets bruts ;
  2. si une stage est `mutableBsp`, sauvegarder une seule fois `stages.json.pre-017`, sans écraser une sauvegarde existante ;
  3. passer en `spatialBsp` et construire l'arbre manquant par `infer`, avec les membres dans l'ordre ;
  4. écriture forcée.

  La fonction renvoie le nombre de stages migrées.
- [x] T023 [US1] Tests dans `Tests/RoadieDaemonTests/StatePersistenceTests.swift` et `StateMigrationTests.swift` :
  - 2 `load` sans écriture font 1 décodage ;
  - une écriture par une autre instance, faite entre un `load` et un `mutate`, n'est pas perdue ;
  - un `mutate` sans changement laisse le mtime inchangé ;
  - un fichier corrompu garde le comportement 016 ;
  - 100 mutations concurrentes ne perdent rien ;
  - migration : sauvegarde créée une seule fois, membres et ordre conservés, stage sans membre migrée, deuxième appel sans effet.

### Lot L3 - Écriture et événements AX, registre, sonde de bureau (Opus) [US1, US2]

- [x] T030 [P] [US2] Créer `Sources/RoadieAX/WrittenFrameRegistry.swift` selon plan.md :
  - frame demandée, relue et acceptée, version de disposition, nombre d'écritures dans la version ;
  - `classify` renvoie `echo` (dernière écriture, à `frameMatch` près), `appResponse` (moins de `echoWindow`) ou `external` ;
  - une frame acceptée est invalidée par une nouvelle version.
- [x] T031 [P] [US1] Dans `AXWindowFrameWriter` (`Sources/RoadieAX/SystemSnapshotProvider.swift`) :
  - écrire dans l'ordre taille, position, taille ;
  - désactiver puis rétablir `AXEnhancedUserInterface`, une fois par pid et par lot, seulement s'il était actif, et le rétablir même en cas d'erreur ;
  - faire une seule relecture via `AXUIElementCopyMultipleAttributeValues` ;
  - appeler `WrittenFrameRegistry.shared.record` à chaque écriture, avec la version de disposition passée par l'appelant (paramètre optionnel, 0 par défaut).
- [x] T032 [P] [US1] Réutiliser l'index `AXApplicationWindows` du dernier snapshot dans l'écrivain : cache par pid, invalidé sur `invalidUIElement`, sur la destruction d'une fenêtre ou à la fin d'une application.
- [x] T033 [P] [US1] Dans `Sources/RoadieAX/AXWindowEventObserver.swift` :
  - observer `kAXWindowMovedNotification` et `kAXWindowResizedNotification` au niveau de l'application ;
  - le callback reçoit `AXWindowEvent { name, pid, windowID? }` ;
  - un déplacement ou redimensionnement classé `echo` par le registre est absorbé dans le callback et ne remonte pas (A1) ;
  - invalider le cache d'attributs par pid ;
  - à la destruction, appeler `WrittenFrameRegistry.forget`.

  Garder l'ancienne signature de callback le temps de la vague 1 si `main.swift` l'utilise encore (A10).
- [x] T034 [P] [US1] Créer `Sources/RoadieAX/SpaceProbe.swift` : `isUserSpaceActive(displayUUID:)` lit en lecture seule `CGSCopyManagedDisplaySpaces`, résolu par `dlsym`, et renvoie `nil` si le symbole est indisponible (A5).
- [x] T035 [US1] Tests dans `Tests/RoadieAXTests/` :
  - ordre des attributs écrits (écrivain espion) ;
  - `AXEnhancedUserInterface` rétabli même en cas d'échec ;
  - une seule énumération par pid et par passe ;
  - registre : écho, réponse de l'application, changement externe, invalidation par version ;
  - écho absorbé dans le callback ;
  - `SpaceProbe` renvoie une valeur ou `nil` sans planter.

### Lot L4 - Moteur à arbre (Opus) [US3, US4]

- [x] T040 [P] [US3] Dans `Sources/RoadieTiler/BSPTree.swift` :
  - le sens de coupe d'une insertion suit la feuille coupée ;
  - ajouter `projected(excluding:)` (feuilles absentes retirées, splits unaires repliés, identité des splits conservée, A9) ;
  - ajouter `balanced()`, `togglingSplit(of:)`, `settingSplit(of:to:)`, `adjustingFence(of:edge:to:in:)` et `correctingForMinimumSize(of:minimum:in:)` (ancêtre de l'axe contraint, `nil` si infaisable, A2) ;
  - écart minimal de 1 px pour la barre de titre.
- [x] T041 [P] [US3] `BSPTree.inferred(from:in:)` reçoit les membres **dans l'ordre**, avec une frame optionnelle. Il détecte les coupes nettes en reprenant `splitHorizontally` et `splitRatio` de `MutableBSPLayoutStrategy.swift:94-207`, sans supprimer ce fichier. Si une frame manque ou est inutilisable, le repli déterministe insère tous les membres dans l'ordre.
- [x] T042 [P] [US3] Dans `Sources/RoadieCore/WindowManagementMode.swift`, ajouter `usesTreeEngine` (vrai pour `spatialBsp` et `mutableBsp`). Dans le parsing de la config, `mutableBsp` et `yabai` donnent `spatialBsp`. Le décodage de `stages.json` est inchangé.
- [x] T043 [P] [US3] `SpatialBSPLayoutStrategy` (`Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift`) place depuis l'arbre projeté.
- [x] T044 [US3] Tests dans `Tests/RoadieTilerTests/` :
  - sens de coupe selon la feuille (écran paysage, 4 insertions, pas de colonnes de 1/8) ;
  - projection : identité des splits, un geste sur la projection modifie le bon split de l'arbre complet ;
  - `balanced`, `togglingSplit`, `adjustingFence` ;
  - `correctingForMinimumSize` : faisable sur l'axe contraint, `nil` si infaisable ;
  - `inferred` : grille, colonnes, lignes, frames manquantes, ordre conservé ;
  - parsing des alias de config.
- [x] T045 [US3] Publier dans le rapport du lot les signatures finales de `BSPTree`.

## Phase 3 : Jonction de la vague 1 (orchestrateur)

- [x] T050 Ajouter à `Sources/RoadieCore/LayoutTolerance.swift` les constantes de plan.md. Poser les stubs compilables (A10) :
  - `LayoutMaintainer.tick(cause:)`, `nextDeadline(now:)` et `spaceDidChange(displayUUID:)` ;
  - `SnapshotService.applyTreeScope(_:cause:)`.

  Build, suite complète, commit de la vague 1.
- [x] T051 Poser aussi :
  - les stubs A20 : `UserInputActivity.currentGesture`, `takeGesture()`, `PlacementGeneration.next()` (compteur global) et le paramètre `generation` de `applyTreeScope` ;
  - le type `layout_stable` dans le catalogue et dans `scripts/measure-layout-reactivity` (stabilité observée = `layout_stable.stableAfterMs` quand il est présent) ;
  - le remplacement des constantes locales de L3 par celles de `LayoutTolerance`.

## Phase 4 : Vague 2

### Lot L6 - Ordonnanceur, sources d'événements, session de geste (Opus) [US1, US2]

- [x] T060 [P] [US1] Créer `Sources/RoadieDaemon/TickScheduler.swift` (`@MainActor`) :
  - garder l'échéance la plus proche et ne jamais abandonner d'événement ;
  - regrouper pendant 15 ms (création, destruction, fin de geste, changement de bureau, commande) ou 30 ms (changement externe) ;
  - aucun tick tant qu'un bouton est enfoncé, puis un tick au relâchement ;
  - un minuteur unique sur `nextDeadline(now:)` ;
  - pas de tick de suite fondé sur « la passe a agi » (A1) ;
  - ouvrir ou continuer l'épisode.
- [x] T061 [P] [US1] Dans `Sources/roadied/main.swift` :
  - remplacer la logique live tick (`pendingLiveTick`, règle des 200 ms) par le `TickScheduler` ;
  - le minuteur périodique devient un filet de sécurité à 2 s ;
  - brancher `AXWindowEvent`, les notifications NSWorkspace (`activeSpaceDidChange` vers `spaceDidChange`, `didActivateApplication`, `didHide`, `didUnhide`) et la fin de « heal » d'écran ;
  - journaliser `activeSpaceDidChange` avec `tsMs`.
- [x] T062 [P] [US2] (A17) Dans `UserInputActivity` (`Sources/RoadieDaemon/FocusFollowsMouseController.swift`), ajouter une session de geste (A4) :
  - au `leftMouseDown`, enregistrer la fenêtre sous le curseur et sa frame ;
  - au `leftMouseUp`, fermer la session et notifier le `TickScheduler` ;
  - exposer `currentGesture` et `lastGesture` ;
  - couvrir tous les boutons pour la suspension ;
  - une session sans cible ne produit aucun geste ;
  - le résultat se consomme une seule fois (`takeGesture()`) ;
  - les moniteurs locaux et globaux alimentent le même état.
- [x] T063 [P] [US1] `Sources/RoadieDaemon/WindowDragActivity.swift` : pas de grâce de fin de glisser pour les modes à arbre ; le relâchement déclenche la passe (A11).
- [x] T064 [US1] Tests dans `Tests/RoadieDaemonTests/TickSchedulerTests.swift`, avec une horloge injectée :
  - l'échéance la plus proche gagne ;
  - aucun événement n'est perdu sous 200 ms ;
  - tick à l'échéance ;
  - aucun tick de suite sur « acted » ;
  - aucun tick bouton enfoncé, puis un tick au relâchement ;
  - un écho ne planifie rien.

### Lot L7 - Cœur du maintainer, étapes séquentielles (Opus) [US1, US2, US3]

- [x] T070 [US1] Étape 1 : durées absolues dans `Sources/RoadieCore/LayoutTolerance.swift`, et suppression de `TickDuration`. Les attentes ne dépendent plus de `intervalSeconds`. Build vert.
- [x] T071 [US1] Étape 2 : passe unique (A1, A15 : état logique sur une copie de travail, puis calcul, puis arbitrage, puis application unique, puis focus). Les étapes de `tick()` (règles, épinglages, focus, zoom, masquage des voisines plein écran, masquage des stages inactives, disposition) alimentent un **plan de passe** dédoublonné par fenêtre, avec l'ordre de priorité de A1, appliqué une fois. Remplir `tick(cause:)` et `nextDeadline(now:)`. Supprimer `run()`. Ajouter à `layout_apply` : `durationMs`, `cause`, `pass`, `scans`, `axWrites`. Build vert.
- [x] T072 [US1] Étape 3 : stabilisation par rafale (A6, A18 : premier placement conservé, une seule passe finale) : au moins 2 changements de membres sur le même scope en moins de `burstWindow`, puis `burstQuiet` de calme, plafond `burstCap`. Un changement isolé déclenche une passe immédiate. Garde de transition de bureau par écran (A5) via `SpaceProbe`, avec repli sur `spaceDidChange` puis une frame stable, plafond `spaceGuardCap`, et `closedBy` = `userSpace` ou `timeout`. Émettre `space_transition_guard`. Build vert.
- [x] T073 [US2] Étape 4 : classement des frames observées (A4, A17 : dépôt prioritaire, position seule ramenée à l'arbre, session consommée une fois), dans cet ordre : session de geste, écho, réponse de l'application, changement externe. Il remplace `lastObservedFrames` relu.
  - Geste sur un mode à arbre : `adjustingFence` sur l'arbre projeté au relâchement, puis une passe, avec `layout_manual_gesture`.
  - Changement externe en mode arbre : une seule réécriture vers l'arbre, avec `layout_external_change_reverted`.
  - Écho et réponse de l'application : `layout_echo_ignored` et `layout_app_response_accepted`.

  Build vert.
- [x] T074 [US2] Étape 5 : budget d'écriture (A2, A13, A14, A16) pour les modes à arbre.
  - Génération globale ouverte par une intention externe ; une correction garde la génération.
  - Refus confirmé par le registre ou par une relecture fraîche à échéance.
  - Un changement externe est ramené une fois par génération, puis accepté.
  - Version de disposition, et 2 écritures au plus par fenêtre et par version, toutes écritures comptées.
  - Refus confirmé par deux observations, puis `correctingForMinimumSize`, puis acceptation. Si la correction est infaisable, accepter le chevauchement.
  - Pour les modes à arbre, ne plus appeler la réparation des voisines par la logique `mutableBsp`, l'exclusion des fenêtres qui refusent de grandir, ni l'isolement des scopes infaisables. Ces mécanismes restent pour `bsp` et `masterStack` (A3).

  Build vert.
- [x] T075 [US2] Étape 6 : tolérance unique (R9). Une frame est « à refaire » si l'écart dépasse `frameMatch` et qu'elle n'est pas la frame acceptée de la version courante.
- [x] T076 [US1] Étape 7 : supprimer la chaîne `mutableBsp` du maintainer (geometry adopted, resize propagated, référence synthétique, `stableVisibleMutableBspScopes`, `revertedAppliedFrames`). Les protections partagées deviennent conditionnelles au mode (A3).
- [x] T077 [US1] Tests dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`. Garder `tiledScopeMembershipChurnSettlesBeforeRelayout` et le test à deux écrans. Ajouter :
  - changement isolé : 1 passe sans attente ;
  - rafale de plusieurs changements ;
  - plafond atteint ;
  - deux écrans indépendants ;
  - activation sans changement de membres ;
  - garde de bureau fermée par `userSpace` puis par `timeout` ;
  - plan unifié : masquage et disposition dans la même passe ;
  - écho à ±5 pt : rien ;
  - oscillation 97/25 px rejouée : 0 propagation ;
  - changement externe : 1 réécriture puis acceptation ;
  - refus : au plus 2 écritures par fenêtre et par version ;
  - repos de 60 s simulé : 0 commande ;
  - `nextDeadline` ;
  - (A18) événements espacés de 80 ms et de 250 ms ;
  - (A15) règle qui change la stage active, avec masquage et disposition dans la même passe ;
  - (A14) refus confirmé sans notification, par relecture fraîche ;
  - (A13) application qui se redimensionne en boucle : une seule réécriture ;
  - (A20) `layout_stable` émis, et épisode ouvert pendant une garde de 1,5 s.

  Réécrire ou retirer, avec justification, les tests `mutableBsp`.

### Lot L8 - Arbre qui fait foi dans le snapshot (Opus) [US1, US3]

- [x] T080 [US3] Dans `Sources/RoadieDaemon/DaemonSnapshot.swift` :
  - pour les modes à arbre (`usesTreeEngine`), aucun intent appliqué sauf le marqueur de zoom ;
  - aucun intent automatique persisté ;
  - disposition depuis l'arbre projeté.
- [x] T081 [US3] Réconcilier l'arbre une seule fois par passe. Insertion à la feuille active, avec le sens selon la feuille. La feuille d'un membre absent est gardée pendant la grâce réelle du membre (30 min), et retirée sur destruction confirmée ou purge du membre (A9).
- [x] T082 [US3] Appeler `StageStore.migrateLegacyTreeModes` une seule fois au démarrage du producteur, avec `BSPTree.inferred` et les conteneurs des écrans. Émettre `state_migrated`.
- [x] T083 [US1] Remplir `applyTreeScope(_:cause:generation:)` (A15 : une commande clôt la rafale ou la garde de son scope) : plan de l'arbre du scope, une application, enregistrement des versions. Après `apply`, republier le snapshot avec les frames relues et invalider seulement les fenêtres en échec (A12). Supprimer la réparation d'ordre (`:1180-1230`) et le seuil « réussi » de 48 pt.
- [x] T084 [US3] Tests dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift` :
  - intent ignoré en mode arbre sauf le zoom ;
  - membre absent depuis plus de 45 s qui reprend sa place ;
  - redimensionnement pendant l'absence d'une voisine, puis retour de la voisine ;
  - migration appelée une seule fois ;
  - un seul snapshot par passe ;
  - `applyTreeScope` en une application.

### Lot L9 - Commandes, bascules et restaurations sur l'arbre (Opus) [US4]

- [x] T090 [P] [US4] Dans `Sources/RoadieDaemon/WindowCommands.swift`, `move`, `swap`, `warp` et `resize` sur l'arbre appliquent par `applyTreeScope`, sans l'attente globale de 2 s. Sens de `resize` : le bord désigné est poussé vers l'extérieur, sinon la frontière opposée est tirée vers l'intérieur.
- [x] T091 [P] [US4] Dans `LayoutCommandService.swift`, `CLICommandRouter.swift` et `WidthAdjustmentService.swift` :
  - `balance` utilise `balanced()` ;
  - `layout toggle-split` utilise `togglingSplit` ;
  - `layout split` utilise `settingSplit` ;
  - `layout flatten` équivaut à `balance` ;
  - `layout insert`, `join-with` et `width` renvoient un refus explicite en mode arbre (code de sortie non nul, message clair).
- [x] T092 [P] [US4] Dans `Sources/RoadieDaemon/DropPreviewController.swift`, construire l'aperçu et le dépôt sur l'arbre projeté : échange au centre, insertion du côté sur un bord. Supprimer le reflow `mutableBsp` et la persistance de l'arbre pendant l'aperçu.
- [x] T093 [P] [US4] `stage_place_window` (`StageCommands.swift`) et le dépôt par le navrail (`RailController.swift`) insèrent dans l'arbre de la stage cible, selon l'index demandé.
- [x] T094 [P] [US1] La bascule de stage (`StageCommands.swift:1029-1041`), la bascule de bureau (`DesktopCommands.swift:308`) et l'aller vers un signet (`WindowBookmarkCommands.swift:117`) posent directement les frames finales de l'arbre pour les modes à arbre, en une application (A11).
- [x] T095 [US4] Tests dans `PowerUserLayoutCommandTests.swift`, `PowerUserDesktopCommandTests.swift` et `DropPreviewEngineTests.swift` :
  - chaque commande des raccourcis BetterTouchTool de l'utilisateur agit en une application ;
  - `toggle-split` et `balance` sur l'arbre ;
  - refus explicite de `insert` et `width` ;
  - glisser au centre ou sur un bord, avec le dépôt qui consomme la session de geste (A17) ;
  - bascule de stage en une application, sans restauration intermédiaire.

## Phase 5 : Vague 3 - Intégration (orchestrateur)

- [x] T100 Supprimer les symboles `mutableBsp` devenus inutilisés : `MutableBSPLayoutStrategy.swift` (après déplacement de la détection de coupes), `LayoutStrategy.mutableBsp` et le code mort restant. Le cas d'enum `WindowManagementMode.mutableBsp` reste pour le décodage.
- [x] T101 Build et suite complète. Corriger les écarts d'interface entre lots.
- [x] T102 [P] Écrire `docs/decisions/009-authoritative-tree-single-pass.md` et `docs/decisions/010-private-space-type-read.md`.
- [x] T103 [P] Mettre à jour `README.md` et `examples/roadies.toml` : `mutableBsp` devient un alias, sens des commandes, nouveaux événements.
- [x] T104 Vérifier par `rg` l'absence dans `Sources/` de `MutableBSPLayoutStrategy`, `TickDuration`, `pendingLiveTick`, `revertedAppliedFrames` et `mutable_bsp_` (hors catalogue obsolète). Mesurer les lignes supprimées (`git diff --stat`).
- [x] T105 Installer (`ROADIE_CODESIGN_IDENTITY="roadied-cert" make install && make stop && make restart`), vérifier `roadie doctor` et la migration (`stages.json.pre-017`), puis mesurer au repos 60 s (SC-003).
- [x] T106 Consigner dans `implementation.md` les mesures avant et après, et ce qui reste à valider à la main (`quickstart.md`, avec la campagne multi-applications et l'application lente).

## Convergence

Passe 1 (2026-10-11). Écarts entre le code réel et la spec (FR, SC, amendements A1 à A20, contrat `contracts/layout-events.md`). Les validations sur macOS réel restent dans T105, T106 et `quickstart.md`.

- [x] T201 [US2] FR-010, R9 : dans `Sources/RoadieTiler/LayoutTypes.swift`, `LayoutDiff.commands` compare les frames avec `LayoutTolerance.frameMatch` (2 pt) au lieu de 1 pt. Aujourd'hui, en mode `bsp` ou `masterStack`, « réussi » (`SnapshotService.apply`, `Sources/RoadieDaemon/DaemonSnapshot.swift:1633`) et « à refaire » utilisent deux tolérances différentes. Résultat : un test montre qu'une fenêtre `bsp` à 1,5 pt de sa cible est classée « appliquée » et n'est pas redemandée à la passe suivante.
- [x] T202 [US3] FR-018 : supprimer de `Sources/RoadieTiler/BSPTree.swift` les API qui n'ont plus d'appelant en production : `warping(_:nextTo:side:containerIsWide:)`, `resizing(window:orientation:delta:)` et `reconciled(liveWindowIDs:focus:side:containerIsWide:)`. Retirer ou réécrire leurs tests (`Tests/RoadieTilerTests/BSPTreeMutationTests.swift`, `BSPTreeTests.swift:147`, `LayoutPlannerTests.swift:224-233`) et justifier le retrait dans `implementation.md`. Résultat : `rg "\.warping\(|resizing\(window:|\.reconciled\(" Sources Tests` ne trouve rien, build et suite verts.
- [x] T203 [US5] FR-016 : ajouter un test automatique de `scripts/measure-layout-reactivity`, lancé par `./scripts/test`, sur un journal de test dans `Tests/RoadieDaemonTests/Fixtures/`. Le journal contient un épisode identifié par `episodeId` (avec `layout_apply` et `layout_stable`) et un épisode ancien sans `tsMs`. Résultat : la sortie `--json` donne, pour chaque épisode, le nombre de passes et la durée jusqu'à stabilité attendus.
- [x] T204 [US4] FR-012, US1.4, US4.1 : les aides `expectAtMostOneWrite` (`Tests/RoadieDaemonTests/PowerUserLayoutCommandTests.swift:323`) et `expectFinalTreeFrames` (`Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift:1317`) réussissent aussi quand aucune écriture n'a lieu. Elles datent du stub de `applyTreeScope`. Exiger exactement une écriture par fenêtre attendue, à la frame de l'arbre. Résultat : les tests `tree*` de move, warp, balance, toggle-split, bascule de stage et bascule de bureau échouent si la commande ne pose pas la disposition.
- [x] T205 [US1] A15 : ajouter à `TreeLayoutMaintainerTests` (`Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`) deux tests : une commande appliquée par `applyTreeScope` pendant une rafale, puis pendant une garde de bureau ouverte, clôt l'attente de ce scope. Résultat : la passe suivante du maintainer écrit sans attendre `burstQuiet` ni `spaceGuardCap`, et `space_transition_guard` porte `closedBy=command`.
- [x] T206 [US2] A17 : ajouter à `TreeLayoutMaintainerTests` (`Tests/RoadieDaemonTests/LayoutMaintainerTests.swift`) les tests manquants. (1) Fenêtre détruite pendant le geste : aucune frontière ajustée, la voisine reprend la place en une passe. (2) Relâchement reçu par le maintainer avant le dépôt (`WindowDragActivity` encore active) : la passe ne consomme pas la session, puis le dépôt la consomme, et aucune frontière n'est ajustée.
- [x] T207 [US5] A12, data-model (un épisode est ouvert par une commande) : `SnapshotService.applyTreeScope` (`Sources/RoadieDaemon/DaemonSnapshot.swift:1034`) ouvre un épisode par `EpisodeContext.begin(cause:)`. Son `layout_apply` porte aussi `pass`, `scans` et `axWrites`, comme celui du maintainer. Résultat : un test montre qu'une bascule de stage produit un `layout_apply` avec un `episodeId` propre et ces trois champs, et `scripts/measure-layout-reactivity` range la bascule dans son propre épisode.
- [x] T208 [US5] Contrat `contracts/layout-events.md` : (1) `cause` suit le vocabulaire du contrat (`ax:<notification>`, `command:<nom>`, `drag`, `deadline:<nom>`, `safety`) dans `LayoutMaintainer.tick(cause:)`, `TickScheduler` et `Sources/roadied/main.swift`, sans changer le classement interne ou externe de `currentGeneration` (`Sources/RoadieDaemon/LayoutMaintainer.swift:418`) ; (2) `layout_manual_gesture` porte `ratio` (`Sources/RoadieDaemon/LayoutMaintainer.swift:891`). Résultat : tests de `TreeLayoutMaintainerTests` adaptés sur la valeur de `cause` et la présence de `ratio`.
- [x] T209 [US5] A20 : dans `Sources/RoadieDaemon/LayoutMaintainer.swift`, `armStabilityCheck` fixe l'échéance depuis la fin de `applyPass`, et non depuis `tickNow` pris avant l'écriture : la lecture de stabilité a lieu au moins 100 ms après la dernière écriture. Une passe de commande (`applyTreeScope`) arme aussi cette vérification. Résultat : un test avec horloge injectée montre `layout_stable` émis à 100 ms ou plus après la fin de l'écriture, et après une bascule de stage.
- [x] T210 [US1] R11, A15 : une passe qui change l'état logique (règle, déplacement d'écran adopté, dérive d'écran) recalcule sa copie de travail depuis les fenêtres déjà relevées, sans second relevé AX (`service.snapshot(followFocus:)` à `Sources/RoadieDaemon/LayoutMaintainer.swift:241`). Résultat : `ruleChangingActiveStageHidesAndLaysOutInOnePass` (`Tests/RoadieDaemonTests/LayoutMaintainerTests.swift:3616`) attend `"scans":"1"` et une seule énumération des fenêtres par le fournisseur.

### Convergence : contre-revue de l'implémentation (Codex, round 3)

- [x] T211 [US1] Échéances (objection 1, bloquante) : `LayoutMaintainer.nextDeadline(now:)` rend l'échéance **réelle**, y compris si elle est déjà passée. Le plancher anti-boucle de 15 ms s'applique seulement à la programmation du minuteur dans `TickScheduler`. `fire()` déclenche la passe pour toute échéance `<= now`. Ajouter un test qui relie le vrai `LayoutMaintainer` au `TickScheduler` avec une horloge contrôlée : fin de rafale, plafond de garde à 1,5 s respecté, confirmation de refus.
- [x] T212 [US4] Plan unique pour les commandes (objection 2, bloquante). La bascule de stage, de bureau et de signet, `window display N`, et le dépôt entre scopes doivent faire :
  1. tous les changements logiques d'abord ;
  2. puis le masquage, la source et la destination dans **un seul** plan arbitré par fenêtre ;
  3. puis une seule application ;
  4. puis le focus.

  Plus aucun `setFrame` intermédiaire. Fichiers : `StageCommands.swift`, `DesktopCommands.swift`, `WindowBookmarkCommands.swift`, `WindowCommands.swift`.
- [x] T213 [US2] Génération et budget sur tous les chemins (objection 3). Chaque commande ouvre une génération à son entrée et la transmet à toutes ses écritures. Les écritures directes (`setFrame`) acceptent une génération. Le budget A13 est contrôlé au point commun d'écriture (`AXWindowFrameWriter`), y compris pour une tentative qui échoue après l'appel AX. Fichiers : `SystemSnapshotProvider.swift`, `DaemonSnapshot.swift`, et les commandes.
- [x] T214 [US1] Recalculer `treeScopes` et les exclusions depuis la copie logique finale de la passe (objection 4). Dans les réparations historiques, vérifier directement `!stage.mode.usesTreeEngine`. Fichier : `LayoutMaintainer.swift`.
- [x] T215 [US2] Lier la frame acceptée à la génération du plan dans `treeCommands` (`DaemonSnapshot.swift:~1153`) (objection 5). Une acceptation d'une génération antérieure ne supprime pas une commande.
- [x] T216 [US2] Ne supprimer un geste que sur la preuve d'un dépôt reconnu pour **cette** session (objection 6). Sans candidat de dépôt, `handleMouseUp` n'arme pas de grâce, et le geste suit A17 (retour à l'arbre ou ajustement de frontière). Fichiers : `DropPreviewController.swift`, `WindowDragActivity.swift`, `LayoutMaintainer.swift`.
- [x] T217 [US2] Exclure les scopes à arbre du rapprochement physique générique `reconcileStableVisibleDisplayDrift` (objection 7). L'adoption n'est permise qu'aux commandes, aux gestes prouvés et aux vrais changements de topologie. Fichier : `LayoutMaintainer.swift`.
- [x] T218 [US2] Une lecture AX échouée (`readFrame` qui rend nil) ne vaut jamais confirmation d'un refus, ni stabilité, ni frame stable de garde (objection 8). La garde exige des observations fraîches et non vides, sinon elle attend le plafond. Fichier : `LayoutMaintainer.swift`.
- [x] T219 [US1] Suivi après `applyTreeScope` (objection 9). Publier le résultat de commande (`SnapshotService.onTreeScopeApplied`) vers le maintainer : fenêtres suivies, génération, échéances de refus et de stabilité. L'ordonnanceur réarme son minuteur sans refaire le placement. Le branchement se fait dans `main.swift`.
- [x] T220 [US4] `focus` directionnel en mode arbre sur les frames projetées de l'arbre, et non sur les frames physiques (objection 10). Fichier : `WindowCommands.swift`.
- [x] T221 [US5] Latence : `live_tick` distingue `requestedDelayMs`, `dueLagMs` (retard entre l'échéance et l'exécution) et `heldByGestureMs`. Sert à expliquer les 69 ms. Fichier : `TickScheduler.swift`.

### Convergence passe 2

Passe 2 (2026-10-11), sur `e77f498`. T201 à T221 sont réalisées et testées (763 tests verts). Quatre écarts restent. Les hypothèses 1, 2 et 3 ont été vérifiées par une sonde jetable, sur une copie du dépôt, avec le câblage de production (registre et génération partagés par le service et le maintainer).

- [x] T222 [US2] FR-005, A3, A13 (suite de T213). Le budget du point commun d'écriture coupe la réparation des modes `bsp` et `masterStack`. Dans une même passe, la chaîne écrit plusieurs fois la même fenêtre dans la génération de la passe : ancrage (`LayoutMaintainer.swift:~2381`), réarrangement aux tailles minimales en 2 essais (`:~2547`), puis isolement (`:~2582`). Au-delà de 2 écritures, l'écriture est refusée sans appel AX.
  - Preuve (sonde) : le scénario de `gridWithTwoClampedWindowsIsRearrangedInsteadOfHidden` ne produit plus `layout_clamped_scope_rearranged`, et les frames finales se chevauchent. Avec le câblage des tests, le réarrangement a lieu.
  - Pourquoi les tests ne le voient pas : dans les tests, le maintainer prend un registre et une génération privés (`LayoutMaintainer.swift:48-49`), le service prend `.shared`, et les doubles n'inscrivent pas leurs écritures.
  - Attendu (A3) : pour un scope sans arbre, le budget ne refuse aucune étape de cette chaîne.
  - Résultat : `gridWithTwoClampedWindowsIsRearrangedInsteadOfHidden` et `mutuallyClampedOversizedWindowsIsolateLargestWindowInsteadOfThrashing` passent aussi avec un écrivain qui inscrit chaque tentative dans le registre et la génération du maintainer. Un test d'arbre montre toujours au plus 2 écritures par fenêtre et par génération.
- [x] T223 [US4] A13, FR-012 (suite de T213). Ces commandes n'ouvrent pas de génération et écrivent dans `PlacementGeneration.shared.current` :
  - `layout width` (`WidthAdjustmentService.swift:70`) ;
  - `layout apply --yes` (`CLICommandRouter.swift:368`) ;
  - `heal` (`DaemonHealth.swift:110`) ;
  - `restore apply` (`RestoreSafetyService.swift:189` et `:354`) ;
  - l'assignation bureau et stage du menu de barre de titre (`WindowContextActions.swift:360-361`). Celle-ci fait en plus deux applications : un masquage, puis une application globale.

  Leurs échos sont absorbés et ne déclenchent aucune passe. La génération reste donc la même entre deux appels. Résultat : le 3e `layout width next` de suite sur la même fenêtre est refusé (`write_budget_exhausted`) sans écriture.
  - Attendu : chaque commande ouvre une génération à son entrée et la passe à toutes ses écritures. L'assignation du menu passe par `applyCommandPlacement`, en un seul plan.
  - Résultat : 3 `layout width next` de suite en `bsp`, avec un écrivain qui tient le registre, donnent 3 écritures. L'assignation bureau et stage du menu réussit `expectSinglePlan` (une application, une génération ouverte par la commande).
- [x] T224 [US1] T211, A1 (pas de boucle). Quand le glisser est dans sa grâce de relâchement (un scope actif sans arbre), ou quand l'accessibilité est refusée, `tick` s'arrête avant `checkStability` et avant le traitement des refus. Pourtant, `nextDeadline` rend encore l'échéance passée (`stability`, `refusal_confirm`, `refusal_correct`). L'ordonnanceur relance alors une passe à chaque plancher de 15 ms, avec un relevé complet à chaque fois.
  - Preuve (sonde, `bsp`, grâce de glisser) : 66 passes en 1 s sur la même échéance de stabilité.
  - Attendu : tant qu'une suspension globale arrête la passe, `nextDeadline` rend la fin de cette suspension (comme pour le réglage des écrans), ou rien si l'accessibilité est refusée.
  - Résultat : un test avec le vrai `TickScheduler` montre au plus une passe pendant la grâce, puis une à sa fin, et aucune passe d'échéance si l'accessibilité est refusée.
- [x] T225 [US5] A20, FR-016. `layout_stable` manque après la correction d'un refus. `armStabilityCheck` (`LayoutMaintainer.swift:1300`) fusionne les cibles dans une seule attente, partagée par tout le processus. Une fenêtre refusée dont la nouvelle cible de l'arbre égale sa frame observée n'est pas réécrite. Son ancienne cible (la taille refusée) reste donc en attente, la vérification échoue, et rien ne la réarme.
  - Preuve (sonde) : dans le scénario de `confirmedRefusalIsCorrectedOnceWithinWriteBudget`, avec les échéances et 3 passes du filet de sécurité, aucun `layout_stable`. L'épisode suivant n'obtient le sien que si la fenêtre refusée est réécrite. Le `stableAfterMs` se compte alors depuis l'écriture non résolue la plus ancienne.
  - Attendu : après une correction, on vérifie les cibles du plan corrigé, ou la frame acceptée. Une vérification ne garde pas les cibles d'une vérification déjà échouée.
  - Résultat : refus corrigé sans réécriture de la fenêtre refusée, puis un `layout_stable` au moins 100 ms après l'écriture de correction. Un épisode suivant émet ensuite son propre `layout_stable`, avec un `stableAfterMs` compté depuis sa propre passe.

### Corrections de validation : installation et redémarrage

- [x] T226 Arrêter l’instance de Roadie ouverte sans arguments, retrouver son PID dans le statut si nécessaire, conserver tout PID vivant non reconnu et recharger le service lors de `make restart`. Confirmer que le PID de launchd est vivant et détient le verrou avant d’annoncer le démarrage. Vérifier ces cas avec des commandes simulées.
- [x] T227 Conserver l’identité de signature lors de `make install` sans variable d’environnement. Reprendre l’empreinte exacte du certificat feuille quand la signature l’indique. Vérifier sa disponibilité avant le remplacement des fichiers. Tester le choix automatique, la priorité du choix explicite et le refus d’une identité disparue, même si un autre certificat porte le même nom.

### Correction de validation : échange de cases de largeurs différentes

- [x] T228 Après un échange entre une grande case et une petite case imbriquée, ajuster ensemble les splits nécessaires pour respecter une taille minimale. Emprunter seulement l’espace nécessaire aux voisines extérieures. Conserver la correction locale quand elle suffit, les minima connus, les bornes de ratio, les marges et les feuilles absentes. Lors de la réparation, fournir le côté minimal supposé existant pour les voisines dont le minimum est inconnu. Reproduire le cas réel à quatre fenêtres : T3 exige 840 pixels ; l’ancienne réparation réduit le terminal de 1235 à 190 pixels. Vérifier aussi le budget d’écriture et la stabilité finale.
