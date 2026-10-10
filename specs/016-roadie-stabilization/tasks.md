# Tasks: Stabilisation de Roadie

**Input**: Design documents from `specs/016-roadie-stabilization/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, reuse-audit.md
**Organisation** : les tâches sont regroupées par lot (propriétaire unique de fichiers, voir plan.md) pour permettre le travail parallèle. Chaque tâche porte l'étiquette de sa user story. `[P]` = parallélisable avec les autres lots.
**Vérification commune** : `./scripts/with-xcode swift build` puis `./scripts/test` après chaque lot ; commit par lot.

## Phase 1 : Setup

- [x] T001 Créer `Sources/RoadieCore/LayoutTolerance.swift` avec les constantes de plan.md (`observedChange`, `fullscreenFrame`, `clampShrink`, `growthMinimum`, `growthRatio`, `innerGapTolerance(gapsInner:)`) et une doc par constante ; résultat : compile, aucune utilisation encore
- [x] T002 Ajouter `StageStore.mutate` et `LayoutIntentStore.mutate` (signature de plan.md « Interfaces ») en délégant temporairement à `state()` + `save()` dans `Sources/RoadieDaemon/StageStore.swift` et `Sources/RoadieDaemon/LayoutIntentStore.swift` ; résultat : interface disponible pour les autres lots (implémentation réelle en T010)

## Phase 2 : Lot A - Persistance (Opus) [US1, US2]

- [x] T010 [P] [US2] Implémenter `JSONPersistence.mutate` (verrou exclusif sur tout le cycle lecture-modification-écriture) et l'écriture conditionnelle (pas d'écriture si octets identiques) dans `Sources/RoadieDaemon/JSONPersistence.swift` ; brancher `StageStore.mutate`/`save` et `LayoutIntentStore` dessus
- [x] T011 [P] [US2] Distinguer fichier absent / illisible (`loadResult`) ; sur illisible : copie `.corrupt-<horodatage>`, message stderr + événement `state.load_failed`, écriture refusée (`StageStore.loadFailure`) dans `JSONPersistence.swift` et `StageStore.swift`
- [x] T012 [P] [US1] Réconciliation d'identité prudente : pas de rattachement si le pid du membre est vivant, distance de cadre ≤ 360 px même pour un candidat unique ; ajouter `PersistentStageMember.pid` optionnel dans `StageStore.swift` (`reconcileWindowIDs`, `bestReplacement`)
- [x] T013 [P] [US1] Grâce de 45 s sur les épinglages (`PersistentWindowPin.missingSince`) dans `StageStore.swift` (`pruneMissingPins`)
- [x] T014 [P] [US1] `updateFrame`/`assign` ne remettent plus `presentationState` à nil quand le paramètre est omis dans `StageStore.swift`
- [x] T015 [P] [US2] `LayoutIntentStore` : `prune` sans écriture si inchangé, grâce de 10 min pour les displays absents dans `Sources/RoadieDaemon/LayoutIntentStore.swift`
- [x] T016 [P] [US2] `RailRuntimeStateStore.setVisibleWidth` et les autres écritures via `mutate` dans `Sources/RoadieDaemon/RailRuntimeState.swift`
- [x] T017 [P] [US2] `EventLog` sûr entre processus (`O_APPEND`, une seule écriture par ligne, rotation sous flock) dans `Sources/RoadieDaemon/EventLog.swift` ; `EventSubscriptionService` remet le curseur à 0 si le fichier rétrécit et n'avance que jusqu'au dernier `\n` dans `Sources/RoadieDaemon/EventSubscriptionService.swift`
- [x] T018 [US2] Tests lot A dans `Tests/RoadieDaemonTests/StatePersistenceTests.swift` : 100 mutations concurrentes (2 processus simulés par threads) sans perte, fichier corrompu conservé et non écrasé, pas d'écriture si inchangé, réconciliation refusée pour pid vivant, grâce des pins, rotation EventLog

## Phase 3 : Lot B - Accessibility (Opus) [US3, US4]

- [x] T020 [P] [US3] Délai AX 0,5 s : `AXUIElementSetMessagingTimeout` sur l'élément système et chaque élément application dans `Sources/RoadieAX/SystemSnapshotProvider.swift`
- [x] T021 [P] [US3] Registre `AXUnresponsiveApps` (pid → reprise 5 s) alimenté par `kAXErrorCannotComplete`/dépassement ; les fenêtres d'une app mise de côté gardent leur dernier état dans `SystemSnapshotProvider.swift`
- [x] T022 [P] [US4] Cache limité aux attributs stables ; plein écran natif, focus, principal, modal relus à chaque snapshot ; pas de cache pour une fenêtre de moins de 500 ms ; `invalidateCache()` appelé par l'observer dans `SystemSnapshotProvider.swift`
- [x] T023 [P] [US3] `apply` regroupé par pid avec résolution unique des éléments (suppression de l'O(n²)), suppression des `Thread.sleep` sur le chemin nominal, pas de repli par cadre si le cadre est nul ou ambigu dans `SystemSnapshotProvider.swift`
- [x] T024 [P] [US4] Activation : remplacer `.activateIgnoringOtherApps` par `activate()` + `kAXFrontmostAttribute` avant `AXRaise`, supprimer l'activation en double dans `SystemSnapshotProvider.swift`
- [x] T025 [P] [US4] Observer AX : vérifier les codes de retour, réessayer l'abonnement (backoff), `kAXUIElementDestroyed` par fenêtre, `.commonModes` dans `Sources/RoadieAX/AXWindowEventObserver.swift`
- [x] T026 [P] [US6] Ajouter le preflight Screen Recording (`CGPreflightScreenCaptureAccess`) dans `Sources/RoadieAX/PermissionSnapshot.swift`
- [x] T027 [US8] Créer la cible `RoadieAXTests` dans `Package.swift` et `Tests/RoadieAXTests/AXUnresponsiveAppsTests.swift` (mise de côté, reprise, cache stable seulement)

## Phase 4 : Lot C - Moteur de disposition (Opus) [US1, US2, US4, US8]

- [x] T030 [US1] Plein écran par commande uniquement si `intent.zoomedWindowID` désigne la fenêtre (amendement R5 bis) ; supprimer la détection par taille (`isCommandFullscreenLike`, `isMaximizedLike`) dans `Sources/RoadieDaemon/LayoutMaintainer.swift`
- [x] T031 [US2] Gardes par scope : plein écran natif, stabilisation et suppression liée à une commande excluent leur scope (`excluding:`) au lieu de `return` ; `lastObservedFrames` mis à jour seulement pour les scopes concernés ; activer un scope n'est plus un changement de membres dans `LayoutMaintainer.swift`
- [x] T032 [US1] `restoreFocusedActiveStageIfNeeded` renvoie `nil` si rien n'est à appliquer et rend visible la fenêtre focalisée cachée dans `LayoutMaintainer.swift`
- [x] T033 [US1] Faisabilité : remplacer la somme largeurs+hauteurs par une comparaison de surfaces minimales et une replanification avec tailles minimales ; masquage en dernier recours journalisé ; implémentation unique `clampedFramesCannotShareContainer` exposée pour D dans `LayoutMaintainer.swift`
- [x] T034 [US1] Refus et échecs mémorisés avec `recordedAt`, expiration 30 s, purge des fenêtres disparues ; la position reste appliquée quand seule la taille est refusée dans `LayoutMaintainer.swift`
- [x] T035 [US4] Suspendre l'application des plans tant que `NSEvent.pressedMouseButtons != 0` (observation conservée) dans `LayoutMaintainer.swift`
- [x] T036 [US4] Axe orthogonal du redimensionnement : ignorer les cadres précédents cachés ou hors `visibleFrame` dans `LayoutMaintainer.swift`
- [x] T037 [US8] Factoriser le bloc « appliquer, réparer, isoler, émettre » en une seule fonction ; corriger le compteur `commands` (repairPlan) ; supprimer la surcharge morte `resizeAxesFor(Set)` dans `LayoutMaintainer.swift`
- [x] T038 [US8] Remplacer les littéraux de tolérance par `LayoutTolerance` dans `LayoutMaintainer.swift`
- [x] T039 [US1] Tests lot C dans `Tests/RoadieDaemonTests/LayoutMaintainerTests.swift` : stage à une fenêtre + nouvelle fenêtre tilée, plein écran natif écran 1 n'arrête pas l'écran 2, focus sur frère caché après toggle fullscreen, grille avec 2 fenêtres clampées non masquée, expiration des refus, souris enfoncée = pas d'apply

## Phase 5 : Lot D - Commandes et tiler (Opus) [US1, US4]

- [x] T040 [P] [US1] `toggleFullscreen` enregistre un intent cohérent portant `zoomedWindowID` (amendement R5 bis) et les cadres réellement appliqués dans `Sources/RoadieDaemon/WindowCommands.swift`
- [x] T041 [P] [US1] Supprimer la détection plein écran par taille au changement de stage ; utiliser `isNativeFullscreen` ou l'intent marqué dans `Sources/RoadieDaemon/StageCommands.swift`
- [x] T042 [P] [US1] Basculer vers une stage dont toutes les fenêtres ont disparu (application absente ou délai court) dans `StageCommands.swift`
- [x] T043 [P] [US4] BSP : sur une feuille, un focus absent de l'arbre est traité comme `nil` dans `Sources/RoadieTiler/BSPTree.swift` ; `reconciled` ne double pas les ID ; doc d'`adoptingRatio` alignée sur le code
- [x] T044 [P] [US4] `MutableBSPLayoutStrategy` : tolérance de gap dérivée de `gapsInner` et `abs()` sur l'écart dans `Sources/RoadieTiler/MutableBSPLayoutStrategy.swift`
- [x] T045 [US8] Vague 2 : `StageCommands` appelle l'implémentation unique de faisabilité (T033) et `LayoutTolerance` ; écritures d'état via `StageStore.mutate` dans `StageCommands.swift` et `WindowCommands.swift`
- [x] T046 [US4] Tests lot D dans `Tests/RoadieTilerTests/LayoutPlannerTests.swift` et `Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift` : insertion BSP avec focus étranger, stage vide atteignable, intent fullscreen marqué

## Phase 6 : Lot E - Snapshot et composants (Opus) [US2, US3, US4]

- [x] T050 [P] [US2] Étendre `ConfigReloadService` : instance partagée, `currentConfig()` avec contrôle de date de modification, dernière config valide gardée, erreur journalisée une fois dans `Sources/RoadieDaemon/ConfigReloadService.swift` ; protéger son état (supprimer l'`@unchecked Sendable` non protégé)
- [x] T051 [US2] `SnapshotService` lit la config via `ConfigReloadService.shared` à chaque snapshot (rechargement à chaud) ; remplacer `(try? RoadieConfigLoader.load()) ?? RoadieConfig()` dans `DaemonSnapshot.swift`, `BorderController.swift`, `FocusFollowsMouseController.swift` (les autres fichiers sont traités par leur lot)
- [x] T052 [US2] `snapshot()` : énumération AX hors verrou, réconciliation dans `StageStore.mutate` ; `intentStore.prune` seulement si `persistStateChanges` ; pas d'écriture si inchangé dans `Sources/RoadieDaemon/DaemonSnapshot.swift`
- [x] T053 [US3] Mémo de snapshot récent (< 150 ms, amendement R7 bis) partagé par les composants lecteurs du même processus dans `DaemonSnapshot.swift`
- [x] T054 [US4] Suivi du focus par la stage : ignorer un focus moins de 500 ms après la disparition d'un membre ou non stable sur deux snapshots dans `DaemonSnapshot.swift`
- [x] T055 [US4] Hystérésis du classement tilable : garder le dernier classement si les attributs ne sont pas lisibles dans `DaemonSnapshot.swift`
- [x] T056 [P] [US4] Focus-souris : agir seulement après un mouvement réel (> 2 px) et sans bouton enfoncé dans `Sources/RoadieDaemon/FocusFollowsMouseController.swift`
- [x] T057 [P] [US3] Bordure : pas de `setFrame`/`orderFront` si cadre et couleur inchangés ; snapshot via le mémo dans `Sources/RoadieDaemon/BorderController.swift`
- [x] T058 [P] [US2] Display actif déterministe (display persisté ou de la fenêtre focalisée) et règles réelles dans `Sources/RoadieDaemon/AutomationSnapshotService.swift`
- [x] T059 [US2] Tests lot E dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift` : lecteur sans écriture, focus système ignoré, hystérésis, rechargement de config, config invalide gardant la précédente

## Phase 7 : Lot F - Cycle de vie (Opus) [US1, US2, US6]

- [x] T060 [P] [US2] Verrou d'instance `flock` pour `run` et `tiler` (`~/.roadies/roadied.lock`) + `roadied.pid` ; `ComponentLockFile` réécrit sur `flock` (plus de test-puis-écriture) dans `Sources/RoadieDaemon/ComponentLockFile.swift` et `Sources/roadied/main.swift`
- [x] T061 [P] [US1] Registre d'arrêt unique pour SIGTERM, SIGINT, SIGHUP : ramène les fenêtres masquées à leur dernière frame visible, marque l'arrêt propre, libère le verrou dans `Sources/roadied/main.swift` et `Sources/RoadieDaemon/RestoreSafetyService.swift`
- [x] T062 [P] [US1] Snapshot de restauration écrit à chaque changement de stage et toutes les 30 s, sans frame masquée (frame de membre) dans `RestoreSafetyService.swift`
- [x] T063 [P] [US1] `restore-watch` surveille le pid du tiler ou de `run`, lancé dans sa propre session ; ajouter `unhideAll()` utilisé par la commande `restore unhide-all` dans `RestoreSafetyService.swift` et `Sources/roadied/main.swift`
- [x] T064 [P] [US1] `HiddenWindowPlacement` : coin réellement adjacent à l'écran le plus à droite (plage y), suivi par ID ; remplacer les copies de `hiddenFrame` hors `LayoutMaintainer`/`StageCommands` dans `Sources/RoadieDaemon/HiddenWindowPlacement.swift`
- [x] T065 [P] [US2] Veille/réveil et verrouillage : suspendre les ticks jusqu'à 3 s après le réveil puis une seule réconciliation ; `--ticks` ne compte pas les ticks live dans `Sources/roadied/main.swift`
- [x] T066 [P] [US6] Écrire `~/.roadies/daemon-status.json` (contrat) et heal léger réutilisant le service du tiler dans `Sources/RoadieDaemon/DaemonHealth.swift`
- [x] T067 [US7] Vague 2 : démarrer `CommandSocketServer` dans `run` et `tiler` dans `Sources/roadied/main.swift`
- [x] T068 [US1] Tests lot F dans `Tests/RoadieDaemonTests/RestoreSafetyServiceTests.swift` : fenêtre masquée restaurée à sa frame visible, snapshot sans frame masquée, verrou d'instance refuse un second détenteur

## Phase 8 : Lot G - Navrail (Sonnet) [US3, US5]

- [x] T070 [P] [US5] Watchers config et recording : fermer chaque descripteur une seule fois (schéma de `startStageStoreWatcher`) dans `Sources/RoadieDaemon/RailController.swift`
- [x] T071 [P] [US5] `WindowPresentationStateResolver` : `maximized` exclu pour une fenêtre tilée seule ; seuils via `LayoutTolerance` dans `Sources/RoadieDaemon/WindowPresentationStateResolver.swift`
- [x] T072 [P] [US5] Rétention des membres : seulement `.nativeFullscreen`, 15 s au plus ; renommer `retainMissingNormalMembers` dans `RailController.swift`
- [x] T073 [P] [US5] Masquage du rail devant une fenêtre agrandie piloté par un réglage `hide_on_maximized` documenté (défaut : masquer en plein écran natif seulement) ; supprimer `fullscreenDisplayIDs` et ses tests s'il devient mort dans `RailController.swift`, `RailSettings.swift`
- [x] T074 [P] [US3] Performance : survol testé sur les cadres du dernier rebuild (0 snapshot) ; timer de redessin actif seulement pendant un fondu ; rebuild seulement si la signature visible change ; `looksBlank` mis en cache à la capture dans `RailController.swift`
- [x] T075 [P] [US3] Vignettes réduites à 2× la largeur d'affichage ; capture via `SCScreenshotManager` avec repli icône ; capture transparente traitée comme vide ; preflight Screen Recording journalisé ; purge en gardant les membres représentés dans `RailController.swift`
- [x] T076 [P] [US3] Drag : snapshot pris au début du drag et réutilisé dans `Sources/RoadieDaemon/DropPreviewController.swift` et `RailController.swift`
- [x] T077 [P] [US5] Interactions : clic global ignoré si le panneau était en passthrough ; `pendingDrag` remis à zéro sans bouton enfoncé ; `revealFrame` limité à son écran ; clic sur le fond d'une carte = activer la stage ; réglage clic vide séparé du drop vide ; le rail n'applique pas de layout en mode overlay ; observer d'écran conservé et `stop()` dans `RailController.swift`, `RailSettings.swift`
- [x] T078 [P] [US5] Event taps : réactiver sur `tapDisabledByTimeout`/`UserInput`, supprimer le runloop imbriqué dans `Sources/RoadieDaemon/TargetOverlayPresenter.swift` ; menu de barre de titre : hit test par ordre CG dans `Sources/RoadieDaemon/TitlebarContextMenuController.swift` ; UUID d'écrans dupliqués tolérés (`uniquingKeysWith`) dans `RailController.swift` et `Sources/RoadieDaemon/TargetHintService.swift`
- [x] T079 [US8] Découper `RailController.swift` en `RailPanel.swift`, `StageCardView.swift`, `RailThumbnailStore.swift`, `RailVisualConfig.swift`, `RailFileWatchers.swift` ; une seule extension `NSColor(hex:)` partagée avec `BorderController.swift` (coordonner avec lot E)
- [x] T080 [US5] Tests lot G dans `Tests/RoadieDaemonTests/WindowPresentationStateResolverTests.swift` et `PowerUserFocusCommandTests.swift` : pas de `maximized` pour une fenêtre seule tilée, rétention 15 s, signature inchangée = pas de rebuild

## Phase 9 : Lot H - CLI (Opus) [US6, US7]

- [x] T090 [US7] Déplacer le dispatch de `Sources/roadie/main.swift` dans `Sources/RoadieDaemon/CLICommandRouter.swift` (sorties dans des tampons, code de retour renvoyé, pas de `exit`) ; `main.swift` devient un client mince
- [x] T091 [US7] Créer `Sources/RoadieDaemon/CommandSocketServer.swift` (contrat `cli-daemon-socket.md`) ; client dans `main.swift` avec repli local et commandes toujours locales
- [x] T092 [P] [US6] Supprimer le chemin codé en dur de `daemon restart` (→ `launchctl kickstart -k gui/$UID/com.roadie.roadied`) ; consigne `./scripts/start` retirée des messages dans `CLICommandRouter.swift`
- [x] T093 [P] [US7] `help`/`-h`/`--help` code 0, `--version`, aide par sous-commande générée depuis la table des commandes, commandes non implémentées étiquetées, `wrap` retiré de l'aide ; action sans changement = code 0 ; `--json` propre à chaque commande ; `cleanup --dry-run` lu dans `CLICommandRouter.swift` et `Sources/roadied/main.swift` (usage seulement, coordonné avec F)
- [x] T094 [P] [US6] `roadie doctor` et `permissions` lisent `daemon-status.json` (daemon, AX, Screen Recording, config) dans `CLICommandRouter.swift` et `Sources/RoadieDaemon/Formatters.swift`
- [x] T095 [US7] Tests lot H dans `Tests/RoadieDaemonTests/CLICommandRouterTests.swift` : codes de retour help/version/no-op, aller-retour socket (serveur et client en processus), repli local si socket absent

## Phase 10 : Lot I - Config et exploitation (Sonnet) [US6]

- [x] T100 [P] [US6] Validation de config : clés inconnues avec suggestion (distance d'édition), erreurs de décodage traduites (`table.clé : attendu X`), tables `fx.rail.*` acceptées, clés sans effet signalées (`[desktops]`, `stage_manager.enabled`, `hide_strategy`) dans `Sources/RoadieCore/Config.swift` ; tests dans `Tests/RoadieDaemonTests/ConfigTests.swift`
- [x] T101 [P] [US6] `scripts/with-xcode` : Xcode.app seulement s'il existe, sinon `xcode-select -p` ; `PATH` étendu ; vérification des prérequis avec message clair
- [x] T102 [P] [US6] `scripts/install` : signature via `ROADIE_CODESIGN_IDENTITY` si défini, sinon ad hoc avec avertissement ; binaires installés hors du dépôt (`~/.local/bin`) et LaunchAgent pointant dessus
- [x] T103 [P] [US6] `Makefile` : `restart` = `launchctl kickstart -k`, `dev-start` = ancien `start`, `uninstall` (restore unhide-all, bootout, suppression plist et binaires) ; `scripts/start` fait une rotation `.1` des logs au lieu de les vider ; `scripts/start-modular` et `scripts/package-dmg` vérifient leurs prérequis
- [x] T104 [P] [US6] Supprimer les chemins `/Users/...` restants (`scripts/btt/roadie-record-toggle.sh`, `README.md`, `README.fr.md`) ; vérifier `grep -rn "/Users/" Sources scripts` vide
- [x] T105 [P] [US6] Créer `examples/roadies.toml`, `examples/skhd/skhdrc`, `examples/karabiner/roadie.json`
- [x] T106 [US6] Docs EN et FR : installation (Command Line Tools), permissions (CLI via daemon, Screen Recording), dépannage (`restore unhide-all`, `doctor`), désinstallation, nouveaux réglages (`hide_on_maximized`), config d'exemple ; ADR `docs/decisions/007-cli-daemon-socket.md` et `docs/decisions/008-state-transactions.md`

## Phase 11 : Lot J - Tests et revue (Haiku) [US8]

- [x] T110 [P] [US8] Remplacer les tests décoratifs (`Tests/RoadieDaemonTests/RoadiedRunFlagsTests.swift`, `ComponentSubcommandTests.swift`, `FileLockTests.swift:57-66`) par des tests du vrai code ou les supprimer ; retirer le `setenv` en suite parallèle
- [ ] T111 [US8] Relecture croisée de chaque lot (diff complet) : code mort, littéraux de tolérance restants, `try?` qui avalent une erreur d'état ; rapport dans `specs/016-roadie-stabilization/implementation.md`

## Phase 12 : Polish

- [x] T120 Build complet + suite complète verts ; `grep -rn "/Users/" Sources scripts` vide ; `CGWindowListCreateImage` et `activateIgnoringOtherApps` absents de `Sources`
- [ ] T121 Mettre à jour `specs/016-roadie-stabilization/implementation.md` (journal par lot : commits, fichiers, tests) et l'index des sessions

## Dépendances

- T001, T002 avant tout lot qui consomme `LayoutTolerance` ou `mutate`.
- Lots A, B, C, E, F, G, H, I en parallèle (vague 1) ; D en parallèle sur T040-T044.
- T045 après T033 et T010 ; T051-T052 après T010 et T050 ; T067 après T091 ; T094 après T066 ; T079 après T070-T078.
- J après les lots concernés ; Polish en dernier.

## Convergence

Passage 1 (2026-10-10) : 6 manques relevés par Converge (T201-T206) et 7 défauts relevés par la contre-revue d'implémentation Codex, vérifiés puis retenus (T207-T212).

- [x] T201 [US4] FR-005 : point d'ancrage BSP = premier élément présent dans l'arbre de la stage parmi focus global, `stage.focusedWindowID`, `stage.previousFocusedWindowID`, sinon `nil`, dans `Sources/RoadieDaemon/DaemonSnapshot.swift` (`reconcileSpatialBSPTrees`, `reconciledBSPTree`) ; test dans `Tests/RoadieDaemonTests/SnapshotServiceTests.swift` (arbre de 3, nouvelle fenêtre voisine de la 2e feuille)
- [x] T202 [US2] FR-013 : convertir à `StageStore.mutate` les `save` restants (`LayoutMaintainer.swift:858, 925, 2367, 2378`, `DaemonHealth.swift:114, 139`, `StateAudit.swift:89`) ; `grep -rn "\.save(" Sources | grep -v -i intent` vide ; test dans `StatePersistenceTests.swift`
- [x] T203 [US2] FR-017 : test deux écrans dans `LayoutMaintainerTests.swift` (stabilisation écran 1 n'empêche pas l'écran 2 ; changement de stage sans `layout_stage_membership_settling`)
- [x] T204 [US8] FR-040 : `LayoutCommandActivity.markActive(reason:scopes:)` et exclusion des seuls scopes concernés dans `LayoutMaintainer.swift:166-179` ; test commande écran 1 / plan écran 2
- [x] T205 [US8] FR-041 : littéraux restants vers `LayoutTolerance` (`DaemonSnapshot.swift:1118-1121, 1435, 1447, 1702-1712, 1767`, `LayoutMaintainer.swift:2980`, `Sources/RoadieTiler/LayoutTypes.swift:99`)
- [x] T206 [US6] FR-033 : rotation `.1` des logs du service installé avant `launchctl kickstart` (`scripts/install`, `scripts/roadiedctl`, `Makefile` restart) ; `FileAdministration.swift:129-145` fait `rotate` au lieu de `delete`
- [x] T207 [US2] FR-013 : `WindowBookmarkCommands.swift:93` et `DesktopCommands.swift:291` calculent le scope à écrire hors verrou ; le retrouver et le modifier DANS le bloc `mutate`, renvoyer les infos nécessaires à l'AX après la transaction
- [x] T208 [US1] FR-002 : le focus sur une voisine cachée d'une fenêtre zoomée sort explicitement du zoom (retrait de `zoomedWindowID`) et relance la disposition du scope dans `LayoutMaintainer.swift` ; adapter `LayoutMaintainerTests.swift:3587` et ajouter un test de changement de géométrie après restauration
- [x] T209 [US1] FR-037 : `RestoreSafetyService.unhideAll` couvre les membres persistés introuvables dans le snapshot visible (recherche hors écran) et une fenêtre restée cachée ou hors écran après `apply` (résultat `.clamped`) compte comme échec ; l'arrêt n'est marqué propre que si aucune fenêtre connue ne reste cachée sans preuve de fermeture ; tests dans `RestoreSafetyServiceTests.swift`
- [x] T210 [US3] FR-021 : `AXWindowEventObserver.watchDestruction` reçoit le pid, traite le résultat et interrompt la boucle après mise de côté ; `noteResult` appliqué aux erreurs intégrées des valeurs multiples dans `SystemSnapshotProvider.swift` ; test dans `Tests/RoadieAXTests/`
- [x] T211 [US4] FR-009 : les snapshots des commandes CLI locales de lecture sont non persistants et sans suivi du focus (`CLICommandRouter.swift`) ; sans moniteur de saisie actif, le suivi du focus par la stage est refusé (comportement conservateur) dans `FocusFollowsMouseController.swift` `allowsFocusChange` ; tests
- [x] T212 [US3] FR-023 : le tiler publie son snapshot comme source partagée et les lecteurs le consomment dans le cycle (producteur unique par processus quand le tiler tourne) dans `DaemonSnapshot.swift` / `LayoutMaintainer.swift` ; test vérifiant qu'un lecteur ne rescanne pas après un tick du tiler

Ajouts du passage 1 issus de la relecture croisée T111 (rattachés à une exigence existante) :

- [x] T213 [US2] FR-013 : pas d'E/S sous le verrou des stages (`DaemonSnapshot.swift` : `newWindowDisplayID` reçoit la config en paramètre) ni sous le verrou de config (`ConfigReloadService.currentConfig` charge hors verrou, publie sous verrou, journalise après)
- [x] T214 [US1] FR-037 : `RestoreSafetyService` n'appelle pas l'AX sous le verrou de reprise (lire le marqueur sous verrou, restaurer hors verrou, revérifier) ; `restore.json` illisible conservé en `.corrupt-<date>` et jamais écrasé (FR-015)
- [x] T215 [US2] FR-015 : `try?` qui avalent une écriture d'état sans log remplacés par `do/catch` + stderr (`LayoutCommandActivity.swift:30,51`, `CommandSocketServer.swift:151`)
- [x] T216 [US8] FR-041 : tolérances littérales restantes de `LayoutMaintainer.swift` (pixels et secondes), `MutableBSPLayoutStrategy.swift:178,222`, `StageCommands.swift:1459-1460` vers `LayoutTolerance` ; défaut 48 de `Rect.isClose` remplacé par un paramètre explicite
- [x] T217 [US2] FR-019 : sonde du verrou d'instance côté client (`CommandSocketServer.isDaemonLockHeld`) sans risque de faire échouer un démarrage concurrent (cohérente avec `ComponentLockFile`)
- [x] T218 [US8] Swift 6 : `@unchecked Sendable` sans garde (`ComponentLockFile`, `AXWindowEventObserver` → `@MainActor`, `LiveSystemSnapshotProvider` → retirer `@unchecked`) ; `nonisolated(unsafe)` redondant dans `DaemonSnapshot.swift:1862`
- [x] T219 [US6] FR-035 : `DaemonHealth.swift:211` traite `EPERM` comme vivant ; un seul test de vivacité de pid partagé (`ProcessLiveness`) utilisé par les 6 sites

Passage 2 (suites de la relecture croisée T111 et des rapports K1-K3, Articles XIX et FR-041) :

- [ ] T220 [US8] Brancher `ProcessLiveness.isAlive` sur les copies restantes (`StageStore.swift` `isProcessAlive`, `ComponentLockFile.swift`, `CLICommandRouter.swift`, `CommandSocketServer.swift`, `TargetMacroService.swift` qui oublie EPERM, `Sources/roadied/main.swift`) ; une seule implémentation
- [ ] T221 [US8] `ApplyResult.empty` dans `DaemonSnapshot.swift` et remplacement des 3 écritures longues (`LayoutMaintainer.swift`, `StageCommands.swift`)
- [ ] T222 [US8] Une seule détection « en test » partagée (`isRunningTests` ×3 et `processName.contains("test")` ×4)
- [ ] T223 [US8] Supprimer le code mort introduit ou laissé, confirmé par rg (`StageStore.loadFailure` si tests seulement → garder et documenter, `RestoreSafetyService.runMarker`, `RailPanel.aspectFitSourceRect`, paramètre inutilisé `positionContent(count:)`, `StageStore.swift:378,417,1304`, `TargetOverlayPresenter.swift:82,118`, `TitlebarContextMenuController.swift:54`, `WindowRuleEngine.swift:104`)
- [ ] T224 [US8] Dédupliquer `TargetOverlayPresenter.reenableEventTap` et `color(hex:fallback:)` (→ `NSColor(hex:)`) ; ramener les copies de `isHidden` (`StageCommands.swift`, `DesktopCommands.swift`, `BorderController.swift`, `DaemonSnapshot.swift`, `WindowBookmarkCommands.swift`) vers `HiddenWindowPlacement`
- [ ] T225 [US4] `StageStore.assign` renseigne `previousFocusedWindowID` quand le focus change ; `correctSoloMaximizedStates` réutilise `WindowPresentationStateResolver.tiledWindowCounts` (variante pour `[ScopedWindowSnapshot]`)
- [ ] T226 [US1] FR-037 : `DaemonSnapshot` ne recopie pas dans un membre de stage un cadre hors de tout écran présent (dernière position visible préservée après disparition d'un écran) ; test
- [ ] T227 [US8] `stage list` lit sans verrou exclusif ; la boucle `scope.updateFrame` de `StageCommands.swift` (~900) précalcule les cadres hors transaction (annotation de complexité)
