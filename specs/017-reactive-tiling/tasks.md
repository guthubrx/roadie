# Tasks: Tiling réactif façon yabai

**Input**: Design documents from `specs/017-reactive-tiling/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, reuse-audit.md
**Organisation** : les tâches sont regroupées par lot. Chaque lot est le propriétaire unique de ses fichiers (voir plan.md). Chaque tâche porte l'étiquette de sa user story. `[P]` signifie parallélisable avec les autres lots de la même vague.
**Vérification commune** : `./scripts/with-xcode swift build` puis `./scripts/test` après chaque lot ; un commit par lot.

## Phase 1 : Setup

- [x] T001 Écrire `specs/017-reactive-tiling/agent-brief.md` : règles de travail parallèle, lecture obligatoire, rapport attendu. Résultat : brief prêt pour les agents.
- [x] T002 Commiter `scripts/measure-layout-reactivity` (mesure de référence déjà produite) et consigner les chiffres « avant » dans `research.md`. Résultat : commande reproductible.

## Phase 2 : Vague 1

### Lot L1 - Instrumentation (Sonnet) [US5]

- [ ] T010 [P] [US5] Ajouter `tsMs` et `episodeId` à `RoadieEvent` dans `Sources/RoadieDaemon/EventLog.swift`, et `tsMs` à l'enveloppe dans `Sources/RoadieCore/AutomationEvent.swift`. Ajouter un contexte d'épisode global au processus, protégé par verrou : `EpisodeContext.begin(cause:)`, `current`. Les champs sont optionnels, et les anciennes lignes se décodent toujours.
- [ ] T011 [P] [US5] Déclarer dans `AutomationEventCatalog.swift` les nouveaux types du contrat (`layout_echo_ignored`, `layout_app_response_accepted`, `layout_manual_gesture`, `space_transition_guard`, `state_migrated`). Marquer les trois types `mutable_bsp_*` comme obsolètes.
- [ ] T012 [P] [US5] Adapter `scripts/measure-layout-reactivity` : utiliser `tsMs` et `episodeId` quand ils sont présents (épisode = `episodeId`, durées en ms), et garder le découpage actuel pour les anciennes lignes.
- [ ] T013 [US5] Tests dans `Tests/RoadieDaemonTests/EventLogTests.swift` (ou le fichier de tests EventLog existant) : décodage d'une ancienne ligne sans les nouveaux champs ; `tsMs` cohérent avec `timestamp` ; `episodeId` posé par le contexte.

### Lot L2 - Cache de l'état persisté (Opus) [US1]

- [ ] T020 [P] [US1] Ajouter dans `Sources/RoadieDaemon/JSONPersistence.swift` un cache par chemin, valeur décodée et signature (mtime ns, taille, inode). La signature réutilise ou étend `fileModificationStamp`, sans dupliquer sa logique. `load` rend la valeur en cache si la signature n'a pas changé. `mutate` part du cache sous verrou, n'encode ni n'écrit si la valeur est égale (`Equatable`), puis met à jour le cache après écriture.
- [ ] T021 [P] [US1] Brancher `StageStore.state()` et `LayoutIntentStore` sur ce cache dans `Sources/RoadieDaemon/StageStore.swift` et `Sources/RoadieDaemon/LayoutIntentStore.swift`. Relire `LayoutCommandActivity` (`Sources/RoadieDaemon/LayoutCommandActivity.swift`) via une signature. Comportements FR-014 et FR-015 de la SPEC-016 inchangés : fichier corrompu conservé, écriture refusée.
- [ ] T022 [US1] Tests dans `Tests/RoadieDaemonTests/StatePersistenceTests.swift` :
  - 2 `load` sans écriture font 1 décodage ;
  - une écriture par une autre instance (même fichier) est vue au `load` suivant ;
  - un `mutate` sans changement laisse le mtime inchangé et ne fait aucun encodage ;
  - un fichier corrompu garde le comportement 016 ;
  - 100 mutations concurrentes ne perdent rien.

### Lot L3 - Écriture et événements AX (Opus) [US1, US2]

- [ ] T030 [P] [US2] Créer `Sources/RoadieAX/WrittenFrameRegistry.swift` selon l'interface de plan.md : `record`, `accept`, `entry`, `forget`, `classify`, avec la tolérance `LayoutTolerance.frameMatch` et la fenêtre `echoWindow`. Classement par la souris : un clic depuis l'écriture signifie un geste.
- [ ] T031 [P] [US1] Dans `AXWindowFrameWriter` (`Sources/RoadieAX/SystemSnapshotProvider.swift`) :
  - écrire dans l'ordre taille, position, taille ;
  - désactiver puis rétablir `AXEnhancedUserInterface`, une fois par pid et par lot, seulement s'il était actif, et le rétablir même en cas d'erreur ;
  - faire une seule relecture via `AXUIElementCopyMultipleAttributeValues` ;
  - appeler `WrittenFrameRegistry.shared.record` à chaque écriture.
- [ ] T032 [P] [US1] Réutiliser l'index `AXApplicationWindows` du dernier snapshot dans l'écrivain (cache par pid, invalidé sur `invalidUIElement`, destruction de fenêtre ou fin d'application). Plus d'énumération `kAXWindows` à chaque écriture.
- [ ] T033 [P] [US1] Dans `Sources/RoadieAX/AXWindowEventObserver.swift` :
  - observer `kAXWindowMovedNotification` et `kAXWindowResizedNotification` au niveau de l'application ;
  - le callback reçoit `AXWindowEvent { name, pid, windowID? }` ;
  - invalider le cache d'attributs par pid au lieu de tout vider ;
  - appeler `WrittenFrameRegistry.forget` à la destruction d'une fenêtre.
- [ ] T034 [US1] Tests dans `Tests/RoadieAXTests/` :
  - ordre des attributs écrits (écrivain espion) ;
  - `AXEnhancedUserInterface` rétabli même en cas d'échec ;
  - une seule énumération par pid et par passe ;
  - classement du registre : écho à ±2 pt, réponse d'application, geste après un clic, frame acceptée.

### Lot L4 - Moteur à arbre (Opus) [US3, US4]

- [ ] T040 [P] [US3] Dans `Sources/RoadieTiler/BSPTree.swift` :
  - le sens de coupe d'une insertion suit la feuille coupée (dimension dominante de son rectangle dans le conteneur), et non le conteneur ;
  - `layout(in:excluding:)` calcule la disposition en ignorant les feuilles absentes ;
  - ajouter `balanced()`, `togglingSplit(of:)`, `settingSplit(of:to:)`, `adjustingFence(of:edge:to:in:)` ;
  - écart minimal de 1 px pour la barre de titre, comme `MutableBSPLayoutStrategy.swift:5`.
- [ ] T041 [P] [US3] `BSPTree.inferred(from:in:)` construit un arbre par détection des coupes nettes, en reprenant `splitHorizontally` et `splitRatio` de `MutableBSPLayoutStrategy.swift:94-207`. Pour des frames vides ou incohérentes, il produit un arbre équilibré dans l'ordre spatial.
- [ ] T042 [P] [US3] Dans `Sources/RoadieCore/WindowManagementMode.swift` et le parsing de la config, lire `mutableBsp` et `yabai` comme `spatialBsp`, aussi bien au décodage de `stages.json` qu'à la lecture de la config. L'écriture enregistre `spatialBsp`. Aucune valeur connue aujourd'hui ne fait échouer le décodage.
- [ ] T043 [P] [US3] `SpatialBSPLayoutStrategy` (`Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift`) utilise `layout(in:excluding:)`. Supprimer `MutableBSPLayoutStrategy.swift` une fois `inferred` déplacé, et retirer `mutableBsp` de `LayoutTypes.swift`.
- [ ] T044 [US3] Tests dans `Tests/RoadieTilerTests/` :
  - sens de coupe selon la feuille (écran paysage, 4 insertions, pas de colonnes 1/8) ;
  - exclusion des absents ;
  - `balanced`, `togglingSplit`, `adjustingFence` ;
  - `inferred` sur 2, 3 et 4 fenêtres en grille, colonnes et lignes ;
  - décodage des anciens modes.

  Réécrire ou retirer, avec justification, les tests `mutableBsp` de `LayoutPlannerTests` et `SpatialBSPConfigTests`.
- [ ] T045 [US3] Publier dans le rapport du lot les signatures finales de `BSPTree` utilisées par les vagues suivantes.

## Phase 3 : Jonction de la vague 1 (orchestrateur)

- [ ] T050 Ajouter à `Sources/RoadieCore/LayoutTolerance.swift` les constantes de plan.md (`frameMatch`, `echoWindow`, `settleQuiet`, `settleCap`, `followUpPassLimit`). Build, suite complète, commit de la vague 1.

## Phase 4 : Vague 2

### Lot L6 - Ordonnanceur et sources d'événements (Opus) [US1]

- [ ] T060 [P] [US1] Créer `Sources/RoadieDaemon/TickScheduler.swift` (`@MainActor`) :
  - garder l'échéance la plus proche et ne jamais abandonner d'événement ;
  - regrouper pendant 15 ms (création, destruction, fin de geste, changement de bureau) ou 30 ms (déplacement, redimensionnement) ;
  - aucun tick tant qu'un bouton de souris est enfoncé, puis un tick au relâchement ;
  - un tick de suite immédiat si la passe a agi, au plus `followUpPassLimit` par épisode ;
  - un minuteur unique sur `maintainer.nextDeadline(now:)` ;
  - ouvrir un épisode (`EpisodeContext.begin`) pour chaque cause.
- [ ] T061 [P] [US1] Dans `Sources/roadied/main.swift` :
  - remplacer la logique live tick (`pendingLiveTick`, règle des 200 ms, coalescence 15/80 ms) par le `TickScheduler` ;
  - le minuteur périodique devient un filet de sécurité à 2 s ;
  - brancher les événements AX (`AXWindowEvent`), les notifications NSWorkspace (`activeSpaceDidChange`, `didActivateApplication`, `didHide`, `didUnhide`) et la fin de « heal » d'écran.
- [ ] T062 [P] [US2] Dans `UserInputActivity` (`Sources/RoadieDaemon/FocusFollowsMouseController.swift`), suivre `leftMouseDown` et `leftMouseUp`, exposer `lastMouseDownAt`, et notifier le relâchement au `TickScheduler`.
- [ ] T063 [US1] Tests dans `Tests/RoadieDaemonTests/TickSchedulerTests.swift`, avec une horloge injectée et un maintainer factice :
  - l'échéance la plus proche gagne, aucun événement n'est perdu sous 200 ms ;
  - tick à l'échéance interne ;
  - au plus N passes de suite ;
  - aucun tick souris enfoncée, puis un tick au relâchement.

### Lot L7 - Cœur du maintainer (Opus) [US1, US2, US3]

- [ ] T070 [US1] Dans `Sources/RoadieCore/LayoutTolerance.swift`, exprimer toutes les durées en secondes absolues et supprimer `TickDuration`. Adapter `Sources/RoadieDaemon/LayoutMaintainer.swift` : les attentes ne dépendent plus de `intervalSeconds`.
- [ ] T071 [US1] Ajouter `tick(cause:) -> TickOutcome` et `nextDeadline(now:)`, qui renvoie la plus proche échéance parmi : resize manuel, fin de stabilisation de chaque scope, topologie d'écran, activité de commande, fin de glisser. Garder `tick()` comme enveloppe. Supprimer `run()`, qui est du code mort.
- [ ] T072 [US1] Stabilisation par période calme : `settleQuiet` sans nouveau changement de membres, plafonnée à `settleCap`, limitée au scope (FR-017 de la SPEC-016). Ajouter une garde de transition de bureau par scope, ouverte à la sortie du plein écran natif ou au retour d'un membre manquant, et fermée par `activeSpaceDidChange` (signal transmis par L6), par une frame stable entre deux lectures, ou par le plafond. Émettre `space_transition_guard`.
- [ ] T073 [US2] Remplacer `lastObservedFrames` relu par le classement de `WrittenFrameRegistry` dans la détection des changements (`changedWindows` et la branche « changed »). Écho : ignoré, avec l'événement `layout_echo_ignored`. Réponse de l'application : acceptée, avec `layout_app_response_accepted`. Geste à la souris sur un mode à arbre : ajustement de la frontière de l'arbre au relâchement (`adjustingFence`), avec `layout_manual_gesture`, puis une passe.
- [ ] T074 [US2] Refus de taille dans les modes à arbre :
  - au premier refus, mémoriser la taille minimale ;
  - ajuster une seule fois le ratio parent et réécrire le sous-arbre ;
  - accepter ensuite (`WrittenFrameRegistry.accept`) ;
  - ne jamais changer la structure de l'arbre à cause d'un refus.

  Supprimer pour les modes à arbre la réparation des voisines par la logique `mutableBsp` (`:1477`) et l'exclusion des fenêtres qui refusent de grandir (`:1165-1193`). L'isolement des scopes infaisables reste en dernier recours.
- [ ] T075 [US2] Tolérance unique (FR-010) : « à refaire » si l'écart dépasse `frameMatch` et que la frame n'est pas la frame acceptée.
- [ ] T076 [US1] Supprimer la chaîne `mutableBsp` (geometry adopted, resize propagated, référence synthétique, `stableVisibleMutableBspScopes`, `revertedAppliedFrames`, `recordObservedFrame` comme référence). Les protections partagées (intents, réparation, attente de commande) deviennent conditionnelles au mode, pour garder `masterStack`, `bsp` et `float`. Ajouter `durationMs`, `cause` et `pass` à `layout_apply`.
- [ ] T077 [US1] Tests dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift` :
  - garder `tiledScopeMembershipChurnSettlesBeforeRelayout` et le test à deux écrans ;
  - ajouter : 1 passe 250 ms après un changement ; plafond de 1,5 s en rafale ; sortie de plein écran : aucune commande pendant la garde, puis 1 passe ;
  - écho à ±5 pt : aucun geste ;
  - reproduction de l'oscillation 97/25 px : 0 propagation ;
  - refus de taille : au plus 2 écritures ;
  - repos de 60 s simulé : 0 commande ;
  - `nextDeadline`.

  Réécrire ou retirer, avec justification, les tests `mutableBsp`.

### Lot L8 - Arbre qui fait foi dans le snapshot (Opus) [US1, US3]

- [ ] T080 [US3] Dans `Sources/RoadieDaemon/DaemonSnapshot.swift`, ne plus appliquer d'intent aux modes à arbre, sauf le marqueur de zoom (`zoomedWindowID`). Ne plus persister d'intent automatique (`persistCurrentLayoutIntents`) pour ces modes.
- [ ] T081 [US3] Réconcilier l'arbre une seule fois par passe (supprimer le doublon `reconcileSpatialBSPTrees` / `reconciledBSPTree`). Insertion à la feuille active avec le sens selon la feuille. Garder la feuille d'un membre absent pendant sa grâce, et la retirer à la purge du membre.
- [ ] T082 [US3] Migration à la première passe :
  - les stages lues comme `spatialBsp`, qui étaient `mutableBsp` et ont des membres avec un arbre vide ou périmé, reçoivent `BSPTree.inferred` depuis les frames actuelles ;
  - sauvegarde `stages.json.pre-017` avant la première écriture migrée ;
  - émettre `state_migrated` une seule fois.
- [ ] T083 [US1] Après `apply`, republier le snapshot partagé avec les frames écrites au lieu de l'invalider. Supprimer la réparation d'ordre (`:1180-1230`) et le seuil « réussi » de 48 pt (FR-010).
- [ ] T084 [US3] Tests dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift` et un nouveau `StateMigrationTests.swift` :
  - migration sur une copie anonymisée de l'état réel (5 stages avec membres) sans perte ni saut ;
  - sauvegarde créée ;
  - intent ignoré en mode arbre sauf le zoom ;
  - membre absent en grâce qui reprend sa place ;
  - un snapshot par passe.

### Lot L9 - Commandes sur l'arbre (Opus) [US4]

- [ ] T090 [P] [US4] Dans `Sources/RoadieDaemon/WindowCommands.swift`, `move`, `swap`, `warp` et `resize` sur l'arbre appliquent le sous-arbre dans la commande, sans l'attente globale de 2 s (`LayoutCommandActivity` limité au scope ou évité). Le sens de `resize` suit celui de `mutableBsp` (le bord désigné est poussé vers l'extérieur, sinon la frontière opposée est tirée vers l'intérieur).
- [ ] T091 [P] [US4] Dans `Sources/RoadieDaemon/LayoutCommandService.swift`, `Sources/RoadieDaemon/CLICommandRouter.swift` et `Sources/RoadieDaemon/WidthAdjustmentService.swift` :
  - `balance` utilise `balanced()` ;
  - `layout toggle-split` utilise `togglingSplit` ;
  - `layout split horizontal|vertical` utilise `settingSplit` ;
  - `layout flatten` équivaut à `balance` ;
  - `layout insert`, `join-with` et `width` renvoient un refus explicite en mode arbre (code de sortie non nul, message clair).
- [ ] T092 [P] [US4] Dans `Sources/RoadieDaemon/DropPreviewController.swift`, construire l'aperçu et le dépôt sur l'arbre : échange au centre, insertion du côté sur un bord (`warping`). Supprimer le reflow `mutableBsp` et la persistance de l'arbre pendant l'aperçu.
- [ ] T093 [P] [US4] `stage_place_window` (`Sources/RoadieDaemon/StageCommands.swift`) et le dépôt par le navrail (`Sources/RoadieDaemon/RailController.swift`) insèrent dans l'arbre de la stage cible, selon l'index d'insertion demandé.
- [ ] T094 [US4] Tests dans `Tests/RoadieDaemonTests/PowerUserLayoutCommandTests.swift`, `PowerUserDesktopCommandTests.swift` et `DropPreviewEngineTests.swift` :
  - chaque raccourci BetterTouchTool de l'utilisateur (liste dans spec, US4) agit en une passe ;
  - `toggle-split` et `balance` sur l'arbre ;
  - refus explicite de `insert` et `width` ;
  - glisser au centre ou sur un bord.

## Phase 5 : Vague 3 - Intégration (orchestrateur)

- [ ] T100 Build et suite complète. Corriger les écarts d'interface entre lots.
- [ ] T101 [P] Écrire `docs/decisions/009-authoritative-tree-single-pass.md` (contexte mesuré, décision R1 à R15, conséquences).
- [ ] T102 [P] Mettre à jour `README.md` et `examples/roadies.toml` : `mutableBsp` devient un alias de `spatialBsp`, sens des commandes, nouveaux événements.
- [ ] T103 Vérifier par `rg` que `MutableBSPLayoutStrategy`, `TickDuration`, `pendingLiveTick`, `revertedAppliedFrames` et `mutable_bsp_` (hors catalogue obsolète) n'apparaissent plus dans `Sources/`. Mesurer les lignes supprimées (`git diff --stat`).
- [ ] T104 Installer (`ROADIE_CODESIGN_IDENTITY="roadied-cert" make install && make stop && make restart`), vérifier `roadie doctor`, puis mesurer au repos 60 s avec `scripts/measure-layout-reactivity` (SC-003).
- [ ] T105 Consigner dans `implementation.md` les mesures avant et après, et ce qui reste à valider à la main (`quickstart.md`).
