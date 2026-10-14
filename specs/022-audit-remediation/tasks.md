# Tasks : Corrections de l'audit v14 complet

Une tâche = un constat. Détail (description, preuve, correction proposée) : `audits/2026-10-13/full-codebase-01/cycle-1/aggregated-findings.json` et `scoring.md`.

## Lot A

- [ ] T001 [A] PERF-001 (HIGH) `Sources/RoadieDaemon/DaemonSnapshot.swift:1692` - La validation des trous de disposition parcourt les fenêtres dans chaque cellule
- [ ] T002 [A] REL-005 (MEDIUM) `Sources/RoadieDaemon/DaemonSnapshot.swift:394` - Le snapshot d’automatisation perd les noms et les stages vides persistées
- [ ] T003 [A] REL-006 (MEDIUM) `Sources/RoadieDaemon/DaemonSnapshot.swift:1978` - Le tri spatial utilise une relation non transitive
- [ ] T004 [A] MIN-002 (LOW) `Sources/RoadieDaemon/DaemonSnapshot.swift:2075` - Neuf surcharges répètent le même encodeur JSON
- [ ] T005 [A] REL-013 (MEDIUM) `Sources/RoadieDaemon/AutomationSnapshotService.swift:101` - La réponse stages ne précise pas l’écran de chaque stage

## Lot B

- [ ] T006 [B] PERF-004 (HIGH) `Sources/RoadieDaemon/LayoutMaintainer.swift:2647` - La réparation de voisinage refait une recherche linéaire pour chaque fenêtre
- [ ] T007 [B] REL-007 (MEDIUM) `Sources/RoadieDaemon/LayoutMaintainer.swift:1860` - Les règles de placement ignorent le rôle AX de la fenêtre
- [ ] T008 [B] REL-008 (MEDIUM) `Sources/RoadieDaemon/LayoutMaintainer.swift:1867` - Une règle différée faute d’écran cible n’est jamais retentée
- [ ] T009 [B] REL-009 (MEDIUM) `Sources/RoadieDaemon/LayoutMaintainer.swift:3087` - Les placements de plusieurs écrans empêchent de sauver leurs dispositions

## Lot C

- [ ] T010 [C] PERF-002 (HIGH) `Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift:28` - Le plan BSP normal reparcourt tout l'arbre pour chaque fenêtre
- [ ] T011 [C] REL-030 (MEDIUM) `Sources/RoadieTiler/LayoutTypes.swift:74` - La configuration master_ratio n'arrive jamais au moteur de disposition
- [ ] T012 [C] REL-031 (MEDIUM) `Sources/RoadieTiler/MasterStackLayoutStrategy.swift:38` - Un espacement trop grand produit une fenêtre hors du conteneur

## Lot D

- [ ] T013 [D] REL-001 (HIGH) `Sources/RoadieDaemon/StageStore.swift:1135` - Des arguments stage invalides peuvent arrêter le daemon
- [ ] T014 [D] PERF-005 (MEDIUM) `Sources/RoadieDaemon/StageCommands.swift:1503` - Les commandes répètent des recherches linéaires évitables
- [ ] T015 [D] REL-023 (MEDIUM) `Sources/RoadieDaemon/StageCommands.swift:586` - Le déplacement --no-follow rend visible une stage inactive

## Lot E

- [ ] T016 [E] REL-002 (HIGH) `Sources/RoadieDaemon/StateAudit.swift:224` - La réparation efface les associations des fenêtres encore ouvertes mais invisibles

## Lot F

- [ ] T017 [F] REL-003 (HIGH) `Sources/RoadieDaemon/TargetModeRuntimeController.swift:152` - Le mode lettres réinterprète la lettre dans une autre liste
- [ ] T018 [F] REL-004 (MEDIUM) `Sources/RoadieDaemon/TargetModeRuntimeController.swift:244` - La grille écran ignore le changement de moniteur demandé par les flèches
- [ ] T019 [F] REL-012 (MEDIUM) `Sources/RoadieDaemon/AppTargetQueryService.swift:706` - Le clic part même si la fenêtre cible ne peut plus être focalisée
- [ ] T020 [F] REL-024 (MEDIUM) `Sources/RoadieDaemon/TargetMacroService.swift:285` - Le replay avale le relâchement de souris si la cible AX est absente
- [ ] T021 [F] REL-025 (MEDIUM) `Sources/RoadieDaemon/TargetMacroService.swift:439` - Les macros perdent le bouton droit et les modificateurs souris
- [ ] T022 [F] TEST-002 (MEDIUM) `Tests/RoadieDaemonTests/TargetModeRuntimeControllerTests.swift:18` - Les tests de cibles ne couvrent pas le raccordement aux effets système

## Lot G

- [ ] T023 [G] REL-016 (MEDIUM) `Sources/RoadieDaemon/DesktopCommands.swift:163` - Déplacer une fenêtre vers son bureau actuel la masque
- [ ] T024 [G] MIN-004 (LOW) `Sources/RoadieDaemon/DesktopCommands.swift:154` - Deux pipelines presque identiques gèrent les déplacements de bureau
- [ ] T025 [G] REL-017 (MEDIUM) `Sources/RoadieDaemon/DisplayParkingService.swift:232` - La reconnexion d’un écran fusionne les stages de bureaux différents
- [ ] T026 [G] REL-020 (MEDIUM) `Sources/RoadieDaemon/HiddenWindowPlacement.swift:34` - Un écran placé à gauche est confondu avec une ancienne zone de masquage
- [ ] T027 [G] REL-026 (MEDIUM) `Sources/RoadieDaemon/WidthAdjustmentService.swift:38` - La commande width sélectionne toujours le premier écran
- [ ] T028 [G] REL-027 (MEDIUM) `Sources/RoadieDaemon/WidthAdjustmentService.swift:57` - Les ajustements relatifs utilisent la largeur de la première fenêtre

## Lot H

- [ ] T029 [H] PERF-003 (HIGH) `Sources/RoadieDaemon/DropPreviewController.swift:480` - La géométrie de groupe copie et fusionne des suffixes en O(n²) pendant le glisser
- [ ] T030 [H] MIN-001 (MEDIUM) `Sources/RoadieDaemon/RailPanel.swift:374` - Le rail recopie des helpers disponibles et conserve un double adaptateur de menu
- [ ] T031 [H] REL-022 (MEDIUM) `Sources/RoadieDaemon/RailController.swift:776` - Le dépôt entre deux rails échoue si leurs stages portent le même identifiant
- [ ] T032 [H] DUP-001 (MEDIUM) `Sources/RoadieDaemon/TitlebarContextMenuController.swift:421` - Le menu recopie trois fois l’exécution et le journal d’une action
- [ ] T033 [H] PERF-006 (MEDIUM) `Sources/RoadieDaemon/TitlebarContextMenuController.swift:205` - Le menu désactivé déclenche quand même un relevé complet à chaque clic droit
- [ ] T034 [H] REL-019 (MEDIUM) `Sources/RoadieDaemon/FocusFollowsMouseController.swift:249` - Le focus souris sélectionne une fenêtre cachée derrière une autre

## Lot I

- [ ] T035 [I] REL-015 (MEDIUM) `Sources/RoadieDaemon/CommandSocketServer.swift:239` - Le PID informatif ne prouve pas que le verrou du daemon est libre
- [ ] T036 [I] PERF-007 (LOW) `Sources/RoadieDaemon/CommandSocketServer.swift:329` - Le lecteur de ligne réanalyse tout le préfixe à chaque paquet
- [ ] T037 [I] REL-018 (MEDIUM) `Sources/RoadieDaemon/EventSubscriptionService.swift:74` - L’abonnement perd des événements lors du remplacement du journal
- [ ] T038 [I] OBS-001 (MEDIUM) `Sources/RoadieDaemon/FileAdministration.swift:140` - La rotation des logs ouverts coupe leur consultation courante
- [ ] T039 [I] REL-021 (MEDIUM) `Sources/RoadieDaemon/JSONPersistence.swift:95` - Une mutation renvoie un succès métier après échec de persistance
- [ ] T040 [I] REL-014 (MEDIUM) `Sources/RoadieDaemon/CLICommandRouter.swift:502` - config reload annonce une application sans changer la configuration du daemon
- [ ] T041 [I] REL-032 (MEDIUM) `scripts/uninstall:28` - La désinstallation laisse une instance autonome active

## Lot J

- [ ] T042 [J] REL-011 (MEDIUM) `Sources/RoadieCore/Config.swift:1702` - Les mauvais types numériques peuvent passer la validation puis devenir des défauts
- [ ] T043 [J] MIN-003 (LOW) `Sources/RoadieCore/Config.swift:1620` - Quatre contrôles de plage portent sur des valeurs déjà bornées
- [ ] T044 [J] REL-010 (MEDIUM) `Sources/RoadieAX/SystemSnapshotProvider.swift:1049` - Le focus annonce un succès lorsque AXRaise échoue sans délai dépassé
- [ ] T045 [J] REL-028 (MEDIUM) `Sources/RoadieDaemon/WindowBookmarkCommands.swift:52` - Focaliser une fenêtre temporairement absente efface son signet
- [ ] T046 [J] REL-029 (MEDIUM) `Sources/RoadieDaemon/WindowRuleAffinityService.swift:178` - Enregistrer une affinité supprime les autres actions des règles générées

## Lot K

- [ ] T047 [K] TEST-001 (MEDIUM) `Tests/RoadieDaemonTests/QueryCommandTests.swift:36` - Le test des requêtes vérifie seulement le nom recopié dans la réponse
- [ ] T048 [K] TEST-003 (MEDIUM) `Tests/RoadieDaemonTests/WindowGroupCommandTests.swift:15` - Le test des commandes de groupe ne contrôle que changed
- [ ] T049 [K] TEST-004 (MEDIUM) `Tests/RoadieDaemonTests/WindowGroupIndicatorTests.swift:20` - Le test de l’indicateur de groupe ne couvre aucun rendu réellement utilisé
- [ ] T050 [K] QUAL-001 (LOW) `README.fr.md:528` - Les guides décrivent des interactions qui ne correspondent plus au code

## Clôture

- [ ] T051 Build + suite complète, contre-revue Codex du diff, corrections de la revue.
- [ ] T052 Nouvel audit v14 (0 HIGH), journal `implementation.md`, validation utilisateur, fusion.
