# Audit Roadie v14 — troisième audit complet

Racine : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation
Branche : 022-audit-remediation. Commit : 4643ae4df4b3390218e9d9acebaa87f878c40b9c. 46 commits au-dessus de main.
Mode readonly ; un cycle ; date 2026-10-13 ; durée 31.5 minutes.
**Note : A — 94.47/100. Livraison bloquée : OUI.**

## Résumé exécutif

15 constats actifs : 3 HIGH, 6 MEDIUM, 6 LOW ; aucun CRITICAL.
Comparaison des 65 constats : {'résolu': 64, 'partiel': 1}. Origine (50) : {'résolu': 49, 'partiel': 1}. Nouveaux audit02 (15) : {'résolu': 15}.
La moyenne ne lève pas le blocage des HIGH. Les nouveaux constats étaient absents des deux rapports précédents ; cela ne prouve pas une régression du quatrième tour.

## Tendance

| Domaine | Audit02 | Actuel | Écart |
|---|---:|---:|---:|
| Global | A 93,21 | A 94.47 | +1.26 |
| security | A 100 | A 100 | 0 |
| supply_chain | A 100 | A 100 | 0 |
| observability | A 98 | A 100 | 2 |
| reliability | D 57 | B 79 | 22 |
| tests | A 100 | A 100 | 0 |
| performance | A 100 | A 100 | 0 |
| complexity | B+ 80 | C 70 | -10 |
| quality | A 100 | A 100 | 0 |
| architecture | A 100 | A 100 | 0 |
| ai_hygiene | A 100 | A 100 | 0 |
| duplication | A 100 | A 100 | 0 |
| minimalism | A 99 | A 97 | -2 |
| ux | A 100 | A 100 | 0 |
| llm_security | N/A  | N/A  | N/A |

Calcul identique : 100 − 25×CRITICAL − 10×HIGH − 3×MEDIUM − LOW par domaine, plancher zéro. Moyenne pondérée, somme des poids 19. Les constats de complexité sont comptés une seule fois, dans complexity. Aucune suppression par baseline.

## Périmètre et vérifications

96 fichiers Swift de production lus intégralement. Tests et documentation par risque. Couverture de lecture production : 100 %. Cette mesure ne certifie pas chaque ligne des tests et documents.
Compilation réussie via swift test. 1112 tests verts, puis 4 tests sûrs de la suite T6 : **1116 tests distincts réussis**. 47 tests non exécutés : 42 dans trois suites à sockets hors scratch et 5 tests du cycle de vie qui arrêtent leurs processus. Les 1163 annoncés ne sont donc pas présentés comme réexécutés intégralement.
Journaux : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/test.log et /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/safe-t6-test.log
Nettoyage du scratch : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/cleanup.json

## Tableau des 65 constats

| Audit | ID | Sévérité initiale | Constat | Statut actuel | Preuve et motif |
|---|---|---|---|---|---|
| 01 | REL-001 | HIGH | Des arguments stage invalides peuvent arrêter le daemon | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1715 — Les deux chemins résiduels signalés dans l'audit02 sont corrigés dans le tour 4 (commit f0acacd4). 1) nextGeneratedStageID utilise addingReportingOverflow(1) et génère un identifiant UUID libre en cas de dépassement (StageCommands.swift:1715). 2) CLICommandRouter.windowID refuse toute valeur ≤ 0, bloquant stage summon 0 et group add/remove/focus avec window ID 0 (CLICommandRouter.swift:327). Les deux sous-cas ont chacun leurs propres tests dans Audit022R4LotT3Tests.swift. |
| 01 | REL-002 | HIGH | La réparation efface les associations des fenêtres encore ouvertes mais invisibles | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StateAudit.swift:255 — Le retrait des membres absents exige un PID connu déclaré mort. Les autres membres restent présents ; la déduplication utilise un Set indépendant de la visibilité. |
| 01 | REL-003 | HIGH | Le mode lettres réinterprète la lettre dans une autre liste | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetModeRuntimeController.swift:256 — La lettre est résolue dans overlay.report.targets conservé, puis cette cible précise est transmise à activate(target:action:). Le présentateur masque ses fenêtres avant activation. |
| 01 | PERF-001 | HIGH | La validation des trous de disposition parcourt les fenêtres dans chaque cellule | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1814 — La détection des trous pré-calcule les intervalles de centres des cadres. Chaque colonne cumule les couvertures par un tableau de différences. Le test frames.contains par cellule a disparu : O(n²) temps et O(n) mémoire. La répétition de cette validation par un appelant est un nouveau défaut distinct, PERF-011. |
| 01 | PERF-002 | HIGH | Le plan BSP normal reparcourt tout l'arbre pour chaque fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift:17 — Vérifié en tour 4 : SpatialBSPLayoutStrategy.swift utilise Set(full.windowIDs) puis leaves.intersection(requested) et l'opérateur present.insert(id).inserted. Le commentaire de ligne 17 confirme le passage de O(n²) à O(n) pour le chemin normal. Le chemin de secours (inserting) reste O(n²) mais n est borné et documenté. |
| 01 | PERF-003 | HIGH | La géométrie de groupe copie et fusionne des suffixes en O(n²) pendant le glisser | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DropPreviewController.swift:488 — Les deux appelants utilisent DropGroupGeometry.planGroup. Une passe unique remplit un seul dictionnaire, sans copie de suffixe ni fusion récursive : O(n). Le calcul de structuralPlacements utilise aussi un Set pour le groupe cible. Aucune régression détectée après tour4. |
| 01 | PERF-004 | HIGH | La réparation de voisinage refait une recherche linéaire pour chaque fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:2690 — La réparation du voisinage construit un Set des IDs des voisines avant le filtre de stage.windowIDs. Le filtre conserve l’ordre et coûte O(n+m). |
| 01 | REL-004 | MEDIUM | La grille écran ignore le changement de moniteur demandé par les flèches | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetModeRuntimeController.swift:348 — Le fournisseur de grille et son activation utilisent la même fermeture rootFor. Un nouvel écran possède sa propre racine de grille. |
| 01 | REL-005 | MEDIUM | Le snapshot d’automatisation perd les noms et les stages vides persistées | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:564 — Les métadonnées persistées sont recopiées dans le RoadieState construit. La fusion ajoute les stages vides, copie nom et mode, conserve les décisions de focus du desktop courant et restaure la stage active des autres desktops et leurs labels. |
| 01 | REL-006 | MEDIUM | Le tri spatial utilise une relation non transitive | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:2116 — Le tri calcule les bandes avant toute comparaison. Chaque fenêtre possède une clé fixe (bande principale, bande secondaire, ID), et les fenêtres sans cadre suivent par ID. Le comparateur ne change plus d’axe selon la paire. |
| 01 | REL-007 | MEDIUM | Les règles de placement ignorent le rôle AX de la fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:1882 — Le contexte du moteur reçoit role, subrole, display, desktop, stage et isFloating. La classification flottante distingue les fenêtres hors mosaïque, épinglées et membres de stages float ; une candidate sans scope retourne nil. |
| 01 | REL-008 | MEDIUM | Une règle différée faute d’écran cible n’est jamais retentée | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:1892 — Une destination indisponible produit deferred. evaluateRules exécute alors continue avant le marquage de la fenêtre comme déjà observée ; la destination peut donc être retentée. |
| 01 | REL-009 | MEDIUM | Les placements de plusieurs écrans empêchent de sauver leurs dispositions | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:3142 — La fusion des résultats d’écriture dans les placements se limite aux membres de la stage courante. Les cadres d’autres écrans ne peuvent plus faire échouer la comparaison des ensembles d’IDs. |
| 01 | DUP-001 | MEDIUM | Le menu recopie trois fois l’exécution et le journal d’une action | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TitlebarContextMenuController.swift:481 — Les trois familles de menus appellent actionTarget, qui délègue à une seule méthode executeAndLog. La construction des destinations reste distincte. Aucune régression détectée après tour4. |
| 01 | MIN-001 | MEDIUM | Le rail recopie des helpers disponibles et conserve un double adaptateur de menu | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:376 — RailPanel réutilise stageCard pour les actions et les charges de glisser (ligne 376). StageCardView partage les cadres de mosaïque et d'icônes entre rendu et sélection (hitPreviewItems ligne 671 réutilise mosaicPreviewFrames/iconPreviewFrames). Le double adaptateur de renommage a disparu. Le partage de la transformation parallax (tour4 REL-040) renforce ce constat. Aucune régression après tour4. |
| 01 | OBS-001 | MEDIUM | La rotation des logs ouverts coupe leur consultation courante | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift:150 — Déjà confirmé résolu en audit02. Le code de rotation de FileAdministration.swift copie vers .1 puis tronque le fichier courant (inode conservé). La logique et les tests sont inchangés entre audit02 et le HEAD du tour 4. |
| 01 | PERF-005 | MEDIUM | Les commandes répètent des recherches linéaires évitables | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1551 — Aucune régression. Les ensembles scopedIDSet (StageCommands.swift:1561) et orderedSet (StageCommands.swift:1616) restent construits hors boucle. La partition visible/vide (stageID(atAssignablePosition:):1672) reste O(s). Commentaires PERF-005 présents. |
| 01 | PERF-006 | MEDIUM | Le menu désactivé déclenche quand même un relevé complet à chaque clic droit | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TitlebarContextMenuController.swift:209 — La garde enabled précède snapshot et le reste du traitement. Les moniteurs restent installés pour le rechargement à chaud. Aucune régression détectée après tour4. |
| 01 | REL-010 | MEDIUM | Le focus annonce un succès lorsque AXRaise échoue sans délai dépassé | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieAX/SystemSnapshotProvider.swift:322 — Le focus exige AXRaise réussi. Les écritures frontmost/focusedWindow refusées nécessitent une confirmation de l’état lu. Les erreurs cannotComplete interrompent la séquence. |
| 01 | REL-011 | MEDIUM | Les mauvais types numériques peuvent passer la validation puis devenir des défauts | **résolu** | : — Confirmation indépendante après lecture intégrale : decodeFlexibleDouble propage le mauvais type aux lignes 1612-1620. |
| 01 | REL-012 | MEDIUM | Le clic part même si la fenêtre cible ne peut plus être focalisée | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:436 — Les deux portées fournissent le windowID. Le clic refuse une identité absente, un focus absent ou un cadre déplacé. L’élément conservé est relu depuis le registre. Le scénario original et son résiduel frontmost_window sont bloqués. |
| 01 | REL-013 | MEDIUM | La réponse stages ne précise pas l’écran de chaque stage | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AutomationSnapshotService.swift:102 — Les stages et groupes publics portent displayId et desktopId. Chaque groupe porte aussi stageId ; les collisions d’identifiants entre écrans sont distinguables. |
| 01 | REL-014 | MEDIUM | config reload annonce une application sans changer la configuration du daemon | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:348 — config reload est routé au daemon par isDaemonRouted ; le routeur utilise le ConfigReloadService partagé injecté. Le rechargement modifie donc le service actif. |
| 01 | REL-015 | MEDIUM | Le PID informatif ne prouve pas que le verrou du daemon est libre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift:224 — Déjà confirmé résolu en audit02. La CLI prend une réservation partagée (reserveLocalExecution) avant tout repli local, le daemon prend le verrou en exclusif avant son PID. La logique de CommandSocketServer.execute est inchangée entre audit02 et le HEAD du tour 4. |
| 01 | REL-016 | MEDIUM | Déplacer une fenêtre vers son bureau actuel la masque | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DesktopCommands.swift:146 — Aucune régression. DesktopCommands.swift:146 continue de refuser le bureau actuel dans les deux entrées publiques. Le corps partagé moveWindow (MIN-004) est inchangé pour ce comportement. |
| 01 | REL-017 | MEDIUM | La reconnexion d’un écran fusionne les stages de bureaux différents | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DisplayParkingService.swift:259 — Aucune régression. DisplayParkingService.swift:259 conserve son regroupement secondaire par bureau (stagesByDesktop) et son scope propre par bureau. |
| 01 | REL-018 | MEDIUM | L’abonnement perd des événements lors du remplacement du journal | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/EventSubscriptionService.swift:99 — Déjà confirmé résolu en audit02. EventSubscriptionService associe décalage et inode, avance le curseur uniquement sur lignes terminées, déduplique les inodes et émet events.gap sur rotation ou troncature. La logique est inchangée entre audit02 et le HEAD du tour 4. |
| 01 | REL-019 | MEDIUM | Le focus souris sélectionne une fenêtre cachée derrière une autre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FocusFollowsMouseController.swift:261 — La première fenêtre à l'écran dans l'ordre du snapshot est choisie avant le filtre d'éligibilité. Une fenêtre non gérée masque donc les fenêtres derrière. Le focus et le départ du glisser partagent cette sélection. Le fournisseur conserve l'ordre CG et inclut les fenêtres non candidates. Aucune régression détectée après tour4. |
| 01 | REL-020 | MEDIUM | Un écran placé à gauche est confondu avec une ancienne zone de masquage | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/HiddenWindowPlacement.swift:41 — Aucune régression. HiddenWindowPlacement.isHiddenOrLegacyOffscreen:38 conserve sa garde d'intersection avec tous les écrans. |
| 01 | REL-021 | MEDIUM | Une mutation renvoie un succès métier après échec de persistance | **partiel** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:187 — Les transferts et zoomParent sont corrigés, mais la lecture intégrale révèle les chemins WindowCommandService.treeCommand et move/warp/resize encore susceptibles d’annoncer aucun changement après persistance ou effet AX. La sortie de zoom a aussi deux écritures dépendantes sans rollback. Voir finding REL-021 de ce complément. |
| 01 | REL-022 | MEDIUM | Le dépôt entre deux rails échoue si leurs stages portent le même identifiant | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailController.swift:776 — La garde compare le couple écran/stage. Deux stages de même identifiant sur des écrans distincts déclenchent le déplacement. Aucune régression détectée après tour4. |
| 01 | REL-023 | MEDIUM | Le déplacement --no-follow rend visible une stage inactive | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:669 — Aucune régression. StageCommands.swift:664-670 conserve ses branches restoring/hiding selon activation effective. |
| 01 | REL-024 | MEDIUM | Le replay avale le relâchement de souris si la cible AX est absente | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:337 — Un clic sémantique complet est tenté avant toute émission brute. S’il échoue, down et up sont rejoués ; le nombre de replis est annoncé. |
| 01 | REL-025 | MEDIUM | Les macros perdent le bouton droit et les modificateurs souris | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:387 — Le bouton et les modificateurs des clics bruts sont conservés. Les combinaisons sans action sémantique fidèle restent brutes. Le nouveau constat sur la molette est distinct de ce défaut de clic souris. |
| 01 | REL-026 | MEDIUM | La commande width sélectionne toujours le premier écran | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WidthAdjustmentService.swift:45 — Aucune régression. WidthAdjustmentService.swift:47-54 conserve la sélection de la fenêtre focalisée avant l'écran/scope. |
| 01 | REL-027 | MEDIUM | Les ajustements relatifs utilisent la largeur de la première fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WidthAdjustmentService.swift:76 — Aucune régression. WidthAdjustmentService.swift:76-78 conserve le ratio de référence depuis la fenêtre active avant le calcul de nudge/preset. |
| 01 | REL-028 | MEDIUM | Focaliser une fenêtre temporairement absente efface son signet | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowBookmarkCommands.swift:63 — Aucune régression. WindowBookmarkCommands.swift:64 conserve sa garde processIsDead avant suppression du signet. |
| 01 | REL-029 | MEDIUM | Enregistrer une affinité supprime les autres actions des règles générées | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleAffinityService.swift:187 — Le rendu des règles sérialise toutes les actions du modèle, dont manage, exclude, floating, layout, gap_override, scratchpad et emit_event. Elles survivent à la sauvegarde d’une affinité. |
| 01 | REL-030 | MEDIUM | La configuration master_ratio n'arrive jamais au moteur de disposition | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/LayoutTypes.swift:22 — Vérifié en tour 4 : LayoutRequest.masterRatio (LayoutTypes.swift:24) existe. LayoutPlanner transmet ce ratio à MasterStackLayoutStrategy.init (LayoutTypes.swift:79). La stratégie exclut les fenêtres newWindowIDs des candidats (MasterStackLayoutStrategy.swift:93-104). |
| 01 | REL-031 | MEDIUM | Un espacement trop grand produit une fenêtre hors du conteneur | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/MasterStackLayoutStrategy.swift:27 — Vérifié en tour 4 : MasterStackLayoutStrategy.swift:30 borne horizontalGap à max(0, rect.width - 2*minimumTileExtent) et verticalGap similairement. BSPTree.gap(for:in:innerGap:) (BSPTree.swift:131) applique la même borne pour les modes BSP. |
| 01 | REL-032 | MEDIUM | La désinstallation laisse une instance autonome active | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/stop:12 — Le commit 13bc4f5a du tour 4 étend scripts/stop pour couvrir les composants modulaires. stop_component arrête rail, border, focus-mouse, titlebar-menu et target-mode depuis leurs fichiers .pid avec attente bornée (50 × 0.1 s) et contrôle d'exécutable. scripts/stop retourne 1 si un composant reste vivant ; scripts/uninstall s'arrête alors sans supprimer. Le commentaire dans uninstall mentionne explicitement 'composants du mode modulaire'. |
| 01 | TEST-001 | MEDIUM | Le test des requêtes vérifie seulement le nom recopié dans la réponse | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/QueryCommandTests.swift:52 — QueryCommandTests décode les réponses en types métier et vérifie IDs, scopes, membres et règles. Inchangé dans le tour4. |
| 01 | TEST-002 | MEDIUM | Les tests de cibles ne couvrent pas le raccordement aux effets système | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/TargetModeRuntimeControllerTests.swift:103 — TargetModeRuntimeControllerTests instancie un vrai contrôleur avec présentateur espion. Les fermetures activate et stateProvider sont exercées. Audit022R4LotT4Tests couvre REL-012/REL-037/REL-038 avec émetteur espion et aucun clic système. Limite explicite maintenue : les frontières Carbon/AX/CGEventTap nécessitent une validation manuelle. |
| 01 | TEST-003 | MEDIUM | Le test des commandes de groupe ne contrôle que changed | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/WindowGroupCommandTests.swift:35 — Aucune régression. WindowGroupCommandTests.swift:26+ vérifie toujours les membres et activeWindowID après chaque étape. Les 6 tests et leurs helpers sont présents. |
| 01 | TEST-004 | MEDIUM | Le test de l’indicateur de groupe ne couvre aucun rendu réellement utilisé | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/BorderController.swift:85 — refresh transmet groupLabel dans BorderRenderModel au panneau réel. BorderView le dessine. Les tests observent les modèles envoyés par refresh. La borne de la pastille est présente. Aucune régression détectée après tour4. |
| 01 | MIN-002 | LOW | Neuf surcharges répètent le même encodeur JSON | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:2231 — SnapshotEncoding contient une seule fonction générique Encodable. Les réglages clés triées et indentation optionnelle sont communs. |
| 01 | MIN-003 | LOW | Quatre contrôles de plage portent sur des valeurs déjà bornées | **résolu** | : — Confirmation indépendante : garde maxDepth et bornes rows/columns supprimées des validateurs ; elles sont déjà appliquées dans les initialiseurs. |
| 01 | MIN-004 | LOW | Deux pipelines presque identiques gèrent les déplacements de bureau | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DesktopCommands.swift:176 — Aucune régression. DesktopCommands.swift:176 conserve le corps partagé moveWindow. Le tour 4 n'a modifié que le contenu de ce corps (commitStageTransfer), sans réintroduire la duplication. |
| 01 | PERF-007 | LOW | Le lecteur de ligne réanalyse tout le préfixe à chaque paquet | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift:393 — Déjà confirmé résolu en audit02. readLine cherche le saut de ligne dans le seul fragment reçu (CommandSocketServer.swift:393). La logique est inchangée entre audit02 et le HEAD du tour 4. |
| 01 | QUAL-001 | LOW | Les guides décrivent des interactions qui ne correspondent plus au code | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/README.fr.md:534 — Les README FR/EN décrivent le glisser au bouton droit. Les deux guides attribuent le drag/drop au rail. Les pages CLI documentent l'exception search_hotkey. Les gestes concordent avec le code. Aucune régression détectée après tour4. |
| 02 | PERF-008 | HIGH | Le plan BSP dwindle reste quadratique sans priorité de redimensionnement | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:152 — Vérifié en tour 4 : BSPLayoutStrategy.splitRatio (BSPLayoutStrategy.swift:154) commence maintenant par `guard !priorityWindowIDs.isEmpty else { return 0.5 }`. Sans priorité, la méthode rend O(1) sans parcourir left ni right. Le commentaire cite explicitement PERF-008. |
| 02 | PERF-009 | HIGH | La réparation des refus reparcourt tous les résultats pour chaque fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:2751 — refusedMinimumSizes indexe une fois tous les résultats avant la boucle des scopes. Chaque minimum du scope combine le plancher, refusedMinimums[id] et clampedFrames[id]. Il n’existe plus de knownMinimumSize parcourant le résultat à chaque fenêtre. Préparation O(r + somme des n des scopes). |
| 02 | REL-033 | MEDIUM | Le mode bsp conserve un espacement qui pousse ses tuiles hors du conteneur | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:86 — Vérifié en tour 4 : splitHorizontally (BSPLayoutStrategy.swift:86-88) appelle maintenant BSPTree.gap(for:.vertical,in:rect,innerGap:) pour effectiveGap. splitVertically (ligne 121) fait de même avec .horizontal. Le second enfant est décalé de effectiveGap (borné), pas de innerGap brut. |
| 02 | REL-034 | MEDIUM | Une valeur default_strategy inconnue est déclarée valide puis remplacée par bsp | **résolu** | : — Confirmation indépendante après lecture intégrale : valeur default_strategy inconnue rejetée aux lignes 166-174. |
| 02 | REL-035 | MEDIUM | L’enregistrement d’une affinité altère encore certaines chaînes de règles | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleAffinityService.swift:150 — Les chaînes vides sont conservées. Le rendu échappe les guillemets, les barres inverses et les caractères de contrôle. saveRules recharge le TOML temporaire et compare les règles avant l’écriture atomique finale. |
| 02 | REL-036 | MEDIUM | Un lecteur garde le glisser actif après son relâchement explicite | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:89 — Le lecteur adopte l’échéance du fichier même si elle raccourcit sa valeur locale. suspensionEnd lit aussi le fichier sans maximum avec l’ancienne échéance. Les max restants dans markActive et finish concernent la prolongation à l’écriture, pas le défaut de lecture initial. |
| 02 | REL-037 | MEDIUM | Les actions de stage perdent le bureau de la cible | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:483 — Les stages des autres bureaux n’exposent que inspect. Les activations directes de switch et send-active comparent aussi le desktopId au bureau courant. |
| 02 | REL-039 | MEDIUM | La réorganisation du rail ignore les stages vides dans le rang transmis | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:397 — Commit 33a18411. La méthode statique persistentReorderPosition calcule le rang dans l'ordre complet des stages (orderedStageIDs, y compris les stages vides), pas seulement parmi les cartes affichées. Les stages vides absentes du rail conservent leur place dans le rang transmis à PersistentStageScope.reorderStage. |
| 02 | REL-040 | MEDIUM | Le mode parallax sélectionne une autre fenêtre que la vignette visible | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCardView.swift:587 — Commit 33a18411. Une méthode statique partagée parallaxTransform(for:rotation:) est utilisée par le dessin (applyParallaxTransform) et le test du clic (hitPreview). hitPreview applique l'inverse de cette transformée au point avant de tester la containance, visant ainsi la forme réellement visible. grabUnit est calculé sur localPoint (dans le repère avant transformation). |
| 02 | MIN-005 | LOW | Le contrôle des raccourcis vides reste inatteignable après leur normalisation | **résolu** | : — Confirmation indépendante : aucune garde .isEmpty des touches déjà normalisées dans validateTargetGrid. |
| 02 | OBS-002 | LOW | Un caractère UTF-8 coupé rend la fin du journal entièrement vide | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/EventLog.swift:233 — Le commit 13bc4f5a du tour 4 corrige EventLog.tail. La sélection des dernières lignes se fait désormais sur les octets bruts (data.split(separator: 10)) AVANT le décodage UTF-8, avec décodage tolérant (String(decoding:as:)). Un préfixe UTF-8 incomplet en tête du tampon ne vide plus le résultat. |
| 02 | OBS-003 | LOW | Le nettoyage annonce applied malgré une suppression refusée | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift:227 — Le commit 13bc4f5a du tour 4 introduit removeReporting dans FileAdministration. Toutes les branches de suppression utilisent ce helper : applied est positionné à true uniquement après removeItem réussi ; un échec écrit sur stderr et retourne false. Le commentaire OBS-003 est présent en ligne 225. |
| 02 | REL-038 | LOW | Une macro tronquée peut rejouer un appui sans son relâchement | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:319 — Le replay mémorise les appuis bruts ouverts, retire ceux normalement relâchés, puis relâche les restants en ordre inverse dans defer. |
| 02 | REL-041 | LOW | Le lanceur de tests laisse son dossier HOME temporaire | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/test:11 — Le commit 13bc4f5a du tour 4 retire exec de scripts/test. La dernière ligne est désormais HOME="$tmp_home" "$script_dir/with-xcode" swift test "$@" sans exec, ce qui permet au shell parent d'exécuter son trap cleanup EXIT. Le commentaire 'Pas de exec (REL-041)' est présent ligne 11. |
| 02 | REL-042 | LOW | Les mots contenus dans un identifiant peuvent transformer un succès sans effet en échec | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:312 — finish lit outcome; actionExitCode compare uniquement .failed. Les noms utilisateur ne déterminent plus le code. Tests T3 et T9 verts : no-op avec failed/not found/unknown et vrais refus de persistance. |

## Findings par sévérité

| ID | Sévérité | Origine | Constat | Emplacement |
|---|---|---|---|---|
| PERF-010 | HIGH | nouveau pour les audits 01/02 ; date d’introduction non déduite | La reconstruction du snapshot rescane toutes les fenêtres pour chaque affectation | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieStages/RoadieState.swift:77 |
| PERF-011 | HIGH | nouveau pour les audits 01/02 ; date d’introduction non déduite | La même disposition est revalidée pour chaque fenêtre modifiée du scope | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:3354 |
| PERF-012 | HIGH | nouveau pour les audits 01/02 ; date d’introduction non déduite | Le rapprochement rescane les mêmes candidats pour chaque membre absent | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageStore.swift:1519 |
| REL-021 | MEDIUM | résiduel | Les commandes de fenêtre conservent encore des écritures après un échec annoncé sans changement | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:187 |
| REL-043 | MEDIUM | nouveau pour les audits 01/02 ; date d’introduction non déduite | Des résultats explicites ne correspondent pas au résultat métier | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:713 |
| REL-044 | MEDIUM | nouveau pour les audits 01/02 ; date d’introduction non déduite | Les actions de cible perdent le statut métier de la commande | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:485 |
| REL-045 | MEDIUM | nouveau pour les audits 01/02 ; date d’introduction non déduite | Les alphabets de ciblage acceptent des lettres identiques qui désignent plusieurs cellules | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1567 |
| REL-046 | MEDIUM | nouveau pour les audits 01/02 ; date d’introduction non déduite | Un lecteur peut supprimer une nouvelle activité de glisser écrite par un autre processus | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:95 |
| REL-049 | MEDIUM | nouveau pour les audits 01/02 ; date d’introduction non déduite | Une table de règles peut écraser les réglages du rail qui la précèdent | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailSettings.swift:377 |
| MIN-006 | LOW | nouveau pour les audits 01/02 ; date d’introduction non déduite | Le contrôle items.isEmpty est impossible après ajout systématique d’un avertissement | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1081 |
| MIN-007 | LOW | nouveau pour les audits 01/02 ; date d’introduction non déduite | Le paramètre args de launch_component est extrait mais jamais utilisé | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/start-modular:61 |
| MIN-008 | LOW | nouveau pour les audits 01/02 ; date d’introduction non déduite | La sélection géométrique d’un écran ne change pas le résultat de conversion | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RoadieScreenCoordinate.swift:25 |
| REL-047 | LOW | nouveau pour les audits 01/02 ; date d’introduction non déduite | Le replay de molette abandonne la position et les modificateurs enregistrés | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:412 |
| REL-048 | LOW | nouveau pour les audits 01/02 ; date d’introduction non déduite | La grille récursive affiche un niveau qui ne peut pas être activé | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetOverlayPresenter.swift:543 |
| REL-050 | LOW | nouveau pour les audits 01/02 ; date d’introduction non déduite | Le démarrage peut être annoncé en échec avant la fin de son initialisation | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/start:79 |

## Détail des findings

### PERF-010 — HIGH — La reconstruction du snapshot rescane toutes les fenêtres pour chaque affectation

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieStages/RoadieState.swift:77
Statut : confirmé par lecture ; scénario système non exécuté.
Description : assignWindow appelle removeWindow, qui traverse tous les scopes et applique removeAll sur leurs fenêtres. Il appelle ensuite insert, qui refait removeAll dans la stage cible. reconcile construit un RoadieState neuf et appelle assignWindow pour chaque fenêtre. Avec un écran, une stage et w fenêtres distinctes, chaque insertion reparcourt les i fenêtres précédentes. Le coût est O(w²), alors que le commentaire de reconcile annonce O(w + m).
Scénario : Fournir au SnapshotService un écran, une stage existante et w fenêtres distinctes non épinglées isTileCandidate=true, puis demander un snapshot. La boucle affecte les fenêtres une à une et rescane les i précédentes. Aucun état corrompu ou entrée invalide n’est nécessaire.
Impact : Travail CPU quadratique à chaque snapshot/reconciliation ; latence non mesurée. HIGH retenu pour le daemon local et l’impact performance, sans allégation de panne mesurée.

```
    public mutating func assignWindow(_ windowID: WindowID, to scope: StageScope) throws {
        guard displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID] != nil else {
            throw RoadieStateError.unknownStage(scope)
        }
        removeWindow(windowID)
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?.insert(windowID)
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?.focusedWindowID = windowID
    }
```

Correction : Construire les appartenances initiales en un passage groupé. Dédupliquer les identifiants avec un Set en conservant l’ordre de dernière occurrence ; affecter chaque tableau de stage une seule fois. Garder assignWindow pour les vrais déplacements, et la restauration ultérieure du focus réel.
Validation : Comparer l’ancien et le nouveau constructeur sur 1 puis plusieurs écrans/bureaux/stages : même ordre windowIDs, même focusedWindowID, mêmes groupes, fenêtres épinglées exclues et dernier doublon conservé. Ajouter un benchmark avec w=50,100,200,400 sur une stage ; vérifier croissance linéaire du constructeur. Aucun benchmark ni test exécuté par cet auditeur.
Effort : S. Risque : MEDIUM.
Contre-audit : CONFIRMED — /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/counter-snapshot.json
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieStages/RoadieState.swift:95 — 
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieStages/RoadieState.swift:171 — 
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:415 — 
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:516 — 

Exemple de correction proposé, non appliqué :

```
// Dans RoadieState : construction initiale uniquement, après création des scopes.
// O(w + s) : w affectations, s scopes alimentés. Le dernier doublon conserve sa position.
public mutating func initializeWindowMemberships(_ assignments: [(WindowID, StageScope)]) throws {
    var reversedIDs: [StageScope: [WindowID]] = [:]
    var seen: Set<WindowID> = []
    for (windowID, scope) in assignments.reversed() {
        guard stage(scope: scope) != nil else { throw RoadieStateError.unknownStage(scope) }
        if seen.insert(windowID).inserted {
            reversedIDs[scope, default: []].append(windowID)
        }
    }
    for (scope, ids) in reversedIDs {
        displays[scope.displayID]?.desktops[scope.desktopID]?.stages[scope.stageID]?
            .setInitialWindowIDs(Array(ids.reversed()))
    }
}

// Dans StageState : utilisé uniquement par la construction ci-dessus, sur un état neuf.
fileprivate mutating func setInitialWindowIDs(_ ids: [WindowID]) {
    windowIDs = ids
    focusedWindowID = ids.last
}

// Dans SnapshotService.reconcile : avant la boucle for window in windows.
var initialMemberships: [(WindowID, StageScope)] = []
// Remplace uniquement state.assignWindow dans cette boucle :
if window.isTileCandidate, pin == nil {
    initialMemberships.append((window.id, scope))
}
// Après la boucle, avant la restauration du focus réel :
do {
    try state.initializeWindowMemberships(initialMemberships)
} catch {
    // Même comportement partiel que les anciens try? individuels si un scope manque.
    for (windowID, scope) in initialMemberships { try? state.assignWindow(windowID, to: scope) }
}
// Conserver les appels setGroups et la restauration ultérieure du focus et des métadonnées.
// assignWindow reste utilisé pour les déplacements d'une fenêtre déjà présente.
```

### PERF-011 — HIGH — La même disposition est revalidée pour chaque fenêtre modifiée du scope

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:3354
Statut : confirmé par lecture ; scénario système non exécuté.
Description : authoritativeModelScopes valide l’intent dans compactMap, avant de dédupliquer les scopes avec Set. Pour k fenêtres modifiées d’un scope de n membres, les mêmes placements passent k fois par validIntent puis intentStillTilesCurrentContainer. Le contrôle des chevauchements parcourt toutes les paires lorsque l’intent est valide ; la détection des trous coûte également O(n²) au pire. Le coût peut donc atteindre O(k·n²), soit O(n³) lorsque k=n. Le cache de JSONPersistence ne mémorise que le JSON décodé ; il ne mémorise pas la validation géométrique.
Scénario : 1. Avoir un scope actif en mode bsp, n fenêtres et un intent de commande valide avec les mêmes n IDs. 2. Faire varier les cadres de k fenêtres au-delà de observedChange entre deux relevés, en gardant leurs centres sur le même écran, sans bouton de souris enfoncé, garde de topologie ou commande active. Une application peut repositionner plusieurs fenêtres avant la passe. 3. changedWindows ajoute tous les IDs modifiés (3332–3341), sans borne k. adoptManualDisplayMoves ne les déplace pas (2166–2167) et le rapprochement des dérives est sauté puisque changedWindowIDs n’est pas vide (278). 4. changedFramesMatchSavedIntent est faux parce que les cadres observés ont changé ; nonTreeLayout appelle authoritativeModelScopes à 744, avant sa garde changedWindowIDs.count >= 2 à 756. 5. L’intent reste géométriquement valide : validIntent contrôle ses placements enregistrés et les IDs présents, pas les cadres courants. Le même calcul est donc exécuté k fois.
Impact : Travail CPU redondant dans la passe de disposition. Le coût croît d’un facteur k pendant les changements groupés. Aucune latence ni consommation chiffrée n’a été mesurée.

```
        Set(snapshot.windows.compactMap { entry -> StageScope? in
            guard windowIDs.contains(entry.window.id),
                  let scope = entry.scope,
                  let stage = snapshot.state.stage(scope: scope),
                  stage.mode == .bsp,
                  snapshot.state.activeScope(on: scope.displayID) == scope,
                  service.hasValidLayoutIntent(scope: scope, in: snapshot)
            else { return nil }
            return scope
        })
```

Correction : Construire l’ensemble des scopes BSP actifs concernés, puis valider chaque scope une seule fois. Conserver les mêmes critères et la même vérification de validité.
Validation : Étendre le scénario externalResizeAfterRecentCommandIntentSnapsBackToCommandLayout à 10, 50 puis 100 fenêtres du même scope et changer plusieurs cadres dans le second relevé. Vérifier les mêmes placements et instrumenter le nombre de validations : une par scope, quelle que soit la quantité de fenêtres modifiées. Comparer le temps de la passe avant/après avec les mêmes fixtures. Tests non exécutés par ce sous-agent.
Effort : S. Risque : LOW.
Contre-audit : CONFIRMED — /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/counter-layout.json
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:740 — Validation du modèle avant la garde de cardinalité à 756.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:3332 — changedWindows retient tous les IDs modifiés.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1569 — hasValidLayoutIntent délègue à validIntent sans cache de validation.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1707 — Identités vivantes puis validation des placements mémorisés.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1766 — Contrôle des chevauchements et des trous.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1884 — Pour un intent valide sans chevauchement, toutes les paires sont comparées.

Exemple de correction proposé, non appliqué :

```
private func authoritativeModelScopes(
    for windowIDs: Set<WindowID>,
    in snapshot: DaemonSnapshot
) -> Set<StageScope> {
    let candidates = Set(snapshot.windows.compactMap { entry -> StageScope? in
        guard windowIDs.contains(entry.window.id),
              let scope = entry.scope,
              snapshot.state.stage(scope: scope)?.mode == .bsp,
              snapshot.state.activeScope(on: scope.displayID) == scope
        else { return nil }
        return scope
    })
    return Set(candidates.filter { scope in
        service.hasValidLayoutIntent(scope: scope, in: snapshot)
    })
}
```

### PERF-012 — HIGH — Le rapprochement rescane les mêmes candidats pour chaque membre absent

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageStore.swift:1519
Statut : confirmé par lecture et contre-audit indépendant ; aucun benchmark exécuté.
Description : L’index bundle+titre évite une recherche dans toutes les fenêtres si les signatures sont distinctes. Dans un groupe de signatures identiques, chaque membre disparu appelle bestReplacement, qui alloue, calcule puis trie toute la liste disponible pour lire seulement les deux meilleurs scores. Le commentaire O(M+W) est donc faux dans ce cas. Cette fonction est appelée par chaque réconciliation de snapshot, sous verrou exclusif dans le producteur.
Scénario : Construire une PersistentStageState avec m membres absents portant tous le même bundle et titre, ancien pid nul ou mort, et des IDs différents des fenêtres vivantes. Fournir w fenêtres vivantes de la même signature, avec cadres en ordre non trié et les deux meilleures distances séparées de moins de 120 : chaque rapprochement est ambigu, aucune fenêtre n’est réclamée. Chaque ancien membre filtre et retrie les mêmes w candidats. Appeler reconcileWindowIDs(with:..., isProcessAlive:{_ in false}) en fixture isolée. Ce cas correspond à une application relancée avec plusieurs fenêtres de titre générique ; les tests actuels couvrent l’ambiguïté sur un membre et deux candidats.
Impact : Travail O(m*w log w) dans la branche de rapprochement et allocations répétées ; ce travail retient le verrou d’état. Le surcoût apparaît pendant le rapprochement de fenêtres après disparition/relance, pas quand tous les IDs sont encore présents. Aucune latence réelle n’a été mesurée.

```
    let available = candidates.filter { !claimed.contains($0.id) }
    guard !available.isEmpty else { return nil }

    // Proximité de cadre exigée même pour un candidat unique (SPEC-016 FR-006) : un titre
    // identique ne suffit pas.
    let scored = available
        .map { window in (window: window, score: frameDistance(member.frame, window.frame)) }
        .sorted { lhs, rhs in lhs.score < rhs.score }
    guard let best = scored.first else { return nil }
    let second = scored.dropFirst().first?.score ?? .greatestFiniteMagnitude
```

Correction : Construire une fois les groupes uniquement avec les fenêtres initialement non revendiquées. Remplacer le tri complet par une recherche des deux meilleurs scores en un passage. Conserver le Set des revendications de la passe pour empêcher les doubles attributions. Pour de gros groupes non résolus, un index géométrique ou une mémoïsation invalidée par les changements est nécessaire si une borne linéaire globale est exigée ; ne pas supprimer la garde d’ambiguïté.
Validation : Conserver les tests de PID vivant/mort, proximité, ambiguïté et candidat nettement meilleur. Ajouter une série de m anciens membres et w fenêtres nouvelles homonymes ambiguës ; instrumenter les visites de candidats. Répéter après adoption des w fenêtres. Le second appel ne doit plus visiter w candidats par ancien membre. Tester qu’aucune fenêtre ne peut être revendiquée par deux anciens membres et que les égalités de scores restent refusées.
Effort : S. Risque : LOW.
Contre-audit : CONFIRMED — /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/counter-reconcile.json
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageStore.swift:639 — Appel du tri pour chaque membre disparu.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:270 — Réconciliation tenue sous le verrou de StageStore.mutate.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:367 — Entrée de la réconciliation des identifiants.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/PersistentStageStateTests.swift:185 — Ambiguïté déjà prévue et testée, sans test de cardinalité.

Exemple de correction proposé, non appliqué :

```
private func bestReplacement(
    for member: PersistentStageMember,
    in candidates: [WindowSnapshot],
    claimed: Set<WindowID>
) -> WindowSnapshot? {
    var best: WindowSnapshot?
    var bestScore = Double.greatestFiniteMagnitude
    var secondScore = Double.greatestFiniteMagnitude
    for window in candidates where !claimed.contains(window.id) {
        let score = frameDistance(member.frame, window.frame)
        if best == nil || score < bestScore {
            secondScore = bestScore
            best = window
            bestScore = score
        } else if score < secondScore {
            secondScore = score
        }
    }
    guard let best, bestScore <= 360, secondScore - bestScore >= 120 else { return nil }
    return best
}
// Construire les listes après claimedWindowIDs, en excluant une fois les fenêtres déjà revendiquées :
var windowsBySignature: [StableWindowSignature: [WindowSnapshot]] = [:]
for window in tileableWindows where !claimedWindowIDs.contains(window.id) {
    windowsBySignature[StableWindowSignature(window: window), default: []].append(window)
}
// Conserver claimedWindowIDs pendant la passe pour interdire toute double réattribution.
// Mettre à jour la documentation : O(M + W + somme des tailles des groupes candidats examinés),
// pas O(M + W) pour une phase de rapprochement géométrique avec plusieurs homonymes.
```

### REL-021 — MEDIUM — Les commandes de fenêtre conservent encore des écritures après un échec annoncé sans changement

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:187
Statut : confirmé par lecture actuelle complète de WindowCommands, StageStore, JSONPersistence, FileLock et LayoutIntentStore ; chaîne restoreZoom relue et concordante avec runtime_full ; pas d’exécution.
Description : Le retour arrière introduit pour les transferts ne couvre pas WindowCommandService.treeCommand. Cette fonction écrit bspTree, puis retire l’intent dans une seconde transaction. Un échec du retrait laisse le nouvel arbre sur disque. Le catch reçoit PersistenceError, pas PartialCommitError, et annonce changed=false. Les chemins move/warp/resize sans arbre ont la variante inverse : ils appliquent les cadres avant persistIntentAfterCommand et annoncent le même refus si cette dernière écriture échoue. La sortie de zoom supprime aussi l’intent avant d’écrire son remplacement, sans transaction commune.
Scénario : Scénario déterministe sans course : fixture isolée avec StageStore inscriptible, une stage spatialBsp active et deux feuilles gauche/droite, fenêtre gauche focalisée. Écrire « { pas du json » dans le fichier du LayoutIntentStore puis appeler WindowCommandService.move(.right). Le snapshot reste possible (prune fait une lecture de repli), activeTree trouve les deux feuilles, mutateChecked permute et persiste les feuilles, removeLayoutIntentChecked lève. Résultat : changed=false, outcome=failed, alors que le BSP persistant est permuté. Une prochaine passe de maintien peut appliquer ce mouvement. Ne pas exécuter contre le daemon de travail.
Impact : Le résultat ne décrit pas l’état conservé. Une opération refusée peut être appliquée plus tard par le maintien ; la disposition de retour d’un zoom peut être perdue.

```
            changed = try stageStore.mutateChecked { state -> Bool in
                let existing = state.bspTree(for: scope) ?? .empty
                let mutated = mutation(existing)
                guard mutated != existing else { return false }
                state.setBSPTree(mutated, for: scope)
                return true
            }
            if changed {
                try service.removeLayoutIntentChecked(scope: scope)
```

Correction : Réutiliser commitStageTransfer pour la mutation d’arbre et le retrait d’intent. Pour move/warp/resize, écrire l’intent avant l’effet, puis restaurer l’état antérieur si tous les cadres sont refusés, ou annoncer explicitement le résultat partiel. Pour la sortie de zoom, remplacer/supprimer l’intent en une seule mutateChecked, sans suppression intermédiaire.
Validation : Ajouter une fixture spatialBsp à deux feuilles et intents corrompus ; vérifier résultat ET égalité de l’arbre après refus. Pour le BSP sans arbre, injecter l’échec dans onFirstFrame et comparer cadres, intent et changed/outcome. Pour la sortie de zoom, provoquer l’échec de la sauvegarde du remplacement et vérifier que l’intent initial et restorePlacements restent présents.
Effort : M. Risque : MEDIUM.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:194 — Pas de rollback avant persistenceFailure.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:64 — Seul PartialCommitError produit changed=true/failed.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:280 — Effet AX avant sauvegarde move ; catch à la ligne 291.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:357 — Même chemin pour warp.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:443 — Même chemin pour resize.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1390 — Entrée throwing de la restauration.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1404 — Suppression de l’intent avant calcul du remplacement.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1416 — Seconde écriture indépendante du remplacement.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/Audit022R4LotT3Tests.swift:175 — Le test d’échec tardif couvre sendToDisplay ; il ne couvre pas move/warp/resize. Le mode des stages principales de cette fixture est bsp, sans arbre.

Exemple de correction proposé, non appliqué :

```
let changed = try service.commitStageTransfer(in: stageStore, { state -> Bool in
    let existing = state.bspTree(for: scope) ?? .empty
    let mutated = mutation(existing)
    guard mutated != existing else { return false }
    state.setBSPTree(mutated, for: scope)
    return true
}, clearingIntentsOf: { $0 ? [scope] : [] })
```

### REL-043 — MEDIUM — Des résultats explicites ne correspondent pas au résultat métier

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:713
Statut : confirmé par lecture de la chaîne commande → écrivain AX → statut CLI ; aucune action AX exécutée.
Description : toggleNativeFullscreen convertit false en noOp. Pourtant, dans l’écrivain AX, false signifie fenêtre/bouton introuvable ou AXPress refusé. La garde « aucune fenêtre active » existe déjà et traite séparément l’action sans objet. La commande CLI termine donc avec le code 0 pour ce refus. Dans les commandes de groupe, le résultat booléen de focus est ignoré : focaliser un ID qui ne fait pas partie du groupe renvoie changed=true sans changer le membre actif.
Scénario : Fixture isolée avec une fenêtre active et un WindowFrameWriting dont toggleNativeFullscreen renvoie false (par exemple l’implémentation par défaut du protocole). Exécuter CLICommandRouter.run(["toggle", "native-fullscreen"]). Le résultat est noOp/code 0 malgré le refus. Équivalent réel : fenêtre encore sélectionnée mais AXPress retourne cannotComplete ou son bouton fullscreen n’est pas disponible. Variante groupe : groupe pair avec membres [1,2], fenêtre 3 existante ; group focus pair 3 laisse activeWindowID=1 mais annonce changed=true/code 0.
Impact : Les scripts et le retour utilisateur prennent un refus pour un succès. Les notifications de changement peuvent aussi être émises sans changement du groupe.

```
        let changed = service.toggleNativeFullscreen(active.window)
        _ = focusWindow(active.window)
        return WindowCommandResult.changedOrNoOp(
            "toggle native-fullscreen: changed=\(changed)",
            changed: changed
        )
```

Correction : Pour le plein écran natif, utiliser changedOrFailed après la garde d’absence de fenêtre. Pour les groupes, transmettre le succès de focus et comparer le groupe avant/après ; annoncer failed si la cible n’est pas membre, noOp si la valeur demandée est déjà présente, changed seulement en cas de modification.
Validation : Ajouter au test CLI une fenêtre active et un écrivain qui refuse toggleNativeFullscreen ; attendre code 1/outcome failed. Conserver le cas sans fenêtre active en code 0/noOp. Dans invalidGroupCommandsLeaveStateUntouched, vérifier aussi le résultat de focus du membre absent ; vérifier noOp sur focus déjà actif.
Effort : S. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieAX/SystemSnapshotProvider.swift:1058 — false couvre l’échec de l’action AX.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:2007 — Le SnapshotService propage le booléen sans transformation.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:313 — Le code de sortie est désormais déterminé exclusivement par outcome.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:720 — Routage toggle native-fullscreen.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowGroupCommands.swift:60 — Le retour du focus de groupe est ignoré.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieStages/RoadieState.swift:223 — La cible hors groupe produit false sans mutation.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowGroupCommands.swift:135 — Annonce systématique changed=true après mutateGroup.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/WindowGroupCommandTests.swift:105 — Le test du membre absent vérifie le store, mais ignore le résultat de commande.

Exemple de correction proposé, non appliqué :

```
return WindowCommandResult.changedOrFailed(
    changed ? "toggle native-fullscreen: changed=true" : "toggle native-fullscreen: action refused",
    changed: changed
)
```

### REL-044 — MEDIUM — Les actions de cible perdent le statut métier de la commande

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:485
Statut : confirmé par lecture du producteur, de l’adaptateur et du trajet CLI ; scénario non exécuté.
Description : La conversion de StageCommandResult vers TargetActionResult ne consulte pas outcome. activateSwitch transforme un noOp de stage déjà active en switch_failed parce que changed est faux. La branche focus écran retire au contraire le statut failed en ne fournissant jamais error. CLICommandRouter calcule alors le code de sortie sur error et inverse le résultat métier. La suppression des mots-clés de REL-042 est bien effective ; ce défaut se situe dans un autre adaptateur.
Scénario : Avec target_mode et picker activés, rester sur une stage S déjà active sur son écran E, sans membre fullscreen natif. Exécuter roadie targets pick "stage:E/D/S" --action switch --json (E/D/S remplacés par l’id exact affiché dans targets list). StageCommandService rend already active et outcome=noOp ; TargetHintService rend switch_failed et la CLI sort avec 1. Cas inverse : si le StageStore est illisible ou refuse une écriture, activer une cible display via targets pick ou targets activate ; DisplayCommandService rend persistenceFailure, mais TargetActionResult.error reste nil et la CLI sort avec 0. Le scénario de stockage se vérifie avec un StageStore temporaire injecté, sans toucher à l’état réel.
Impact : Les scripts et le mode cible reçoivent de faux échecs pour une action idempotente et de faux succès pour un échec réel de sauvegarde. Aucune nouvelle perte de données démontrée.

```
        if let refused = refusedOutsideCurrentDesktop(target, displayID: displayID) { return refused }
        let result = StageCommandService(service: service, store: stageStore, events: eventLog).switchTo(stageID, displayID: DisplayID(rawValue: displayID))
        return TargetActionResult(changed: result.changed, message: result.message, target: target, error: result.changed ? nil : "switch_failed")
```

Correction : Faire dépendre error du statut explicite outcome pour toutes les conversions de résultats métier en TargetActionResult. Conserver changed indépendamment : un résultat partiel peut changer l’état et rester failed. Ajouter une conversion commune et tester les trajets targets pick/activate.
Validation : Tester la conversion des trois outcomes et de changed=true/outcome=failed. Sur le vrai routeur avec services injectés : stage déjà active -> error nil, exitCode 0 ; StageStore refusant la sauvegarde lors du focus écran -> error non nil, exitCode 1.
Effort : S. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:465 — Le résultat du focus écran est converti sans error, même si outcome vaut failed.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1192 — Déjà active, sans changement écran ni activation native : changedOrNoOp donne noOp.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DisplayCommands.swift:46 — Une mutation checked refusée rend persistenceFailure.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:67 — persistenceFailure rend failed, même pour un résultat partiel changed=true.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:1430 — targets pick : code de sortie 0 si error nil, sinon 1.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:1474 — targets activate utilise la même règle.

Exemple de correction proposé, non appliqué :

```
private func targetResult<R: CommandResult>(_ result: R, target: RoadieTarget, failureCode: String) -> TargetActionResult {
    TargetActionResult(changed: result.changed, message: result.message, target: target,
                       error: result.outcome == .failed ? failureCode : nil)
}
// activateSwitch : return targetResult(result, target: target, failureCode: "switch_failed")
// focus écran : return targetResult(result, target: target, failureCode: "display_focus_failed")
// Appliquer la même conversion à focus fenêtre, bookmark et send-active.
```

### REL-045 — MEDIUM — Les alphabets de ciblage acceptent des lettres identiques qui désignent plusieurs cellules

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1567
Statut : confirmé par lecture et sonde Swift pure exécutée (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/probe.log).
Description : La validation compte les caractères bruts sans imposer leur unicité après conversion en majuscules. TargetHintService.labels conserve les doublons et uppercased les labels. TargetGridService.frame choisit ensuite le premier index correspondant au label. Un alphabet assez long mais répété produit plusieurs cellules portant le même chemin ; les suivantes ne sont pas adressables et le clic retombe sur la première.
Scénario : Configurer [experimental.target_grid] enabled=true et hint_characters="aaaaaaaaa" avec la grille 3x3 par défaut. config validate ne signale pas d’erreur sur cette valeur. Le rapport de grille produit neuf cellules A. Demander grid click A clique toujours le centre de la cellule en haut à gauche. Variante app_targets : hint_characters="aA" donne deux cibles portant A.
Impact : La grille personnalisée peut cliquer une autre cellule que celle repérée visuellement. Les labels d’application peuvent devenir ambigus. Réglage utilisateur spécifique requis.

```
    private static func validateTargetGrid(_ config: TargetGridConfig) -> [ConfigValidationItem] {
        var items: [ConfigValidationItem] = []
        if config.hintCharacters.count < config.rows * config.columns {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_grid.hint_characters",
                message: "must contain at least rows*columns characters"
            ))
        }
```

Correction : Valider des labels normalisés, distincts et composés d’un seul caractère après conversion en majuscules. Pour la grille, vérifier au moins rows*columns labels utilisables distincts ; pour les applications, au moins deux. Refuser l’alphabet invalide lors de son chargement ou de l’activation, pas seulement dans un rapport optionnel.
Validation : Tester les alphabets "aaaaaaaaa", "aA", un caractère dont les majuscules comportent plusieurs caractères, et un alphabet unique valide. Vérifier l’unicité des cell.path et l’aller-retour cell(path) vers le centre de chaque cellule.
Effort : S. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1548 — 
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:518 — 
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:539 — 
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetGridService.swift:359 — 

Exemple de correction proposé, non appliqué :

```
let labels = config.hintCharacters.map { String($0).uppercased() }
let validAlphabet = labels.allSatisfy { $0.count == 1 } && Set(labels).count == labels.count
// Rejeter si !validAlphabet ; vérifier ensuite le nombre de labels distincts requis.
```

### REL-046 — MEDIUM — Un lecteur peut supprimer une nouvelle activité de glisser écrite par un autre processus

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:95
Statut : plausible : entrelacement interprocessus établi par lecture ; course non reproduite.
Description : isActive lit le fichier partagé puis le supprime s’il était expiré au moment de la lecture. NSLock protège seulement cette instance. Ni l’écriture atomique du producteur ni le lecteur d’un autre processus ne partagent ce verrou. Le rename du producteur peut donc être suivi par la suppression basée sur l’ancienne lecture. La course est distincte de REL-036, qui corrige le cache de l’échéance.
Scénario : Processus A : lire à la ligne 86 un fichier dont l’échéance est passée, puis être suspendu avant la ligne 95. Processus B : exécuter markActive ou finish ; writeActiveUntilLocked écrit par rename une nouvelle échéance, et finish peut aussi écrire la preuve de dépôt. Processus A : reprendre et supprimer le chemin à la ligne 95. Le nouveau contenu de B est perdu. Le lecteur A ou un troisième lecteur voit ensuite un fichier absent et n’a pas l’échéance récente en mémoire. En mode séparé, la preuve de dépôt lue par lastDrop peut aussi être perdue.
Impact : La nouvelle suspension ou la preuve de dépôt peut disparaître. La garde globale de bouton de souris limite les écritures pendant l’appui ; elle ne restaure pas la grâce de relâchement ni la preuve perdue après le dépôt.

```
        let stored = readLocked()
        // Le fichier partagé fait foi, y compris quand `release` raccourcit l'échéance (REL-036) ;
        // la mémoire locale ne sert que si le fichier est absent ou illisible.
        if let stored { activeUntil = stored.expiry }
        if now <= activeUntil {
            return includingReleaseGrace || (stored?.dragging ?? (activeWindowID != nil))
        }
        activeWindowID = nil
        activeUntil = .distantPast
        try? FileManager.default.removeItem(at: url)
```

Correction : Garder isActive en lecture seule : ignorer l’échéance expirée sans supprimer le fichier, comme LayoutCommandActivity.activity. Le prochain producteur remplace le petit fichier. Si une purge physique est exigée, elle doit être coordonnée avec les écritures par le même verrou interprocessus.
Validation : Test avec deux instances partageant un fichier et une barrière entre lecture et branche expirée du lecteur : écrire une nouvelle activité puis laisser le lecteur finir. Vérifier que le fichier récent et la preuve de dépôt sont conservés. Vérifier aussi les tests REL-036 et les scénarios de dépôt interprocessus.
Effort : S. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:7 — NSLock local à chaque instance.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:101 — Écriture atomique sans FileLock partagé.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:225 — L’activité suspend les passes avant le plan.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:252 — lastDrop empêche de retraiter un geste déjà consommé.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DropPreviewController.swift:617 — Le contrôleur termine un dépôt en publiant droppedWindowID.

Exemple de correction proposé, non appliqué :

```
public func isActive(now: Date = Date(), includingReleaseGrace: Bool = true) -> Bool {
    guard enabled else { return false }
    lock.lock()
    defer { lock.unlock() }
    let stored = readLocked()
    if let stored { activeUntil = stored.expiry }
    if now <= activeUntil {
        return includingReleaseGrace || (stored?.dragging ?? (activeWindowID != nil))
    }
    activeWindowID = nil
    activeUntil = .distantPast
    return false
}
```

### REL-049 — MEDIUM — Une table de règles peut écraser les réglages du rail qui la précèdent

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailSettings.swift:377
Statut : confirmé par lecture et sonde Swift pure exécutée (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/probe.log).
Description : Le parseur propre au rail ne reconnaît que les en-têtes [table]. Lorsqu’il rencontre [[rules]], il conserve current. Les clés de la règle sont alors insérées dans la section précédente jusqu’au prochain en-tête simple. Ce problème préexiste au quatrième tour ; il est nouvellement relevé dans ce complément.
Scénario : Charger exactement : [fx.rail.stage_labels]\nenabled = true\n[[rules]]\nid = "disabled-terminal"\nenabled = false\n[rules.match]\napp = "Terminal"\n[rules.action]\nfloating = true\n (remplacer les \n par des retours à la ligne). Le TOML est composé de tables et clés supportées. RailSettings.load(raw:) renvoie stageLabel.enabled=false car le deuxième enabled écrase le premier. Ajouter ou désactiver cette règle masque donc les noms des stages.
Impact : Configuration valide mais comportement visuel incorrect et dépendant de l’ordre des tables. Le même écrasement peut toucher un en-tête du rail qui partage une clé avec une table de règles.

```
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.hasPrefix("[[") {
                current = String(trimmed.dropFirst().dropLast())
                continue
            }
            guard let current, let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            sections[current, default: [:]][key] = value
```

Correction : Quitter explicitement la section courante lors de tout en-tête [[...]]. À plus long terme, lire ces sections avec TOMLKit, déjà utilisé par la validation, afin de ne pas maintenir deux interprétations de TOML.
Validation : Ajouter un test de RailSettings.load(raw:) avec le scénario : stageLabel.enabled reste true, alors que RoadieConfigLoader lit rules[0].enabled=false. Vérifier aussi deux règles successives et une table [[fx.rail.preview.stage_overrides]]. Aucun de ces tests n’a été exécuté pendant ce complément.
Effort : S. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailSettings.swift:223 — enabled est lu dans la section fx.rail.stage_labels produite par ce parseur.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1090 — La validation utilise TOMLDecoder ; les tables rail et rules ainsi que leurs clés enabled sont connues aux lignes 1180, 1191, 1229 et 1244.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailController.swift:820 — Le rafraîchissement charge RailSettings puis RailVisualConfig directement.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailVisualConfig.swift:302 — enabled est transmis tel quel à RailStageLabelConfig.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCardView.swift:181 — Le dessin des noms est conditionné par config.stageLabel.enabled.

Exemple de correction proposé, non appliqué :

```
private static func sections(from raw: String) -> [String: [String: String]] {
    var sections: [String: [String: String]] = [:]
    var current: String?
    for line in raw.components(separatedBy: .newlines) {
        let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        if trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") {
            current = nil
            continue
        }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            current = String(trimmed.dropFirst().dropLast())
            continue
        }
        guard let current, let equals = trimmed.firstIndex(of: "=") else { continue }
        let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        let value = trimmed[trimmed.index(after: equals)...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        sections[current, default: [:]][key] = value
    }
    return sections
}
```

### MIN-006 — LOW — Le contrôle items.isEmpty est impossible après ajout systématique d’un avertissement

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1081
Statut : confirmé par lecture ; scénario système non exécuté.
Description : Dans le chemin où le fichier de configuration manque, items reçoit toujours un avertissement avant le contrôle isEmpty. validateGeneratedRules ajoute des éléments, sans retirer l’avertissement. Le bloc qui ajoute un succès est inatteignable.
Scénario : Valider un chemin de configuration absent. Le tableau contient toujours au moins l’avertissement « config file not found ».
Impact : Trois lignes inutiles entretiennent l’idée incorrecte qu’un succès peut être ajouté dans cette branche.

```
        guard FileManager.default.fileExists(atPath: resolved) else {
            items.append(
                ConfigValidationItem(level: .warning, path: resolved, message: "config file not found; defaults will be used")
            )
            items.append(contentsOf: validateGeneratedRules(path: generatedPath))
            if items.isEmpty {
                items.append(ConfigValidationItem(level: .ok, path: resolved, message: "config is valid"))
            }
            return ConfigValidationReport(items: items)
```

Correction : Supprimer uniquement le if items.isEmpty et son corps aux lignes 1081-1083.
Validation : Les sorties de validate(path:) pour un chemin absent restent identiques, avec ou sans règles générées.
Effort : XS. Risque : LOW.

Exemple de correction proposé, non appliqué :

```
items.append(contentsOf: validateGeneratedRules(path: generatedPath))
return ConfigValidationReport(items: items)
```

### MIN-007 — LOW — Le paramètre args de launch_component est extrait mais jamais utilisé

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/start-modular:61
Statut : confirmé par lecture ; scénario non exécuté.
Description : Le tableau COMPONENTS encode les composants sous la forme 'nom:args' (ex. 'tiler:run-tiler --yes'). La boucle extrait les deux parties et passe $args comme second paramètre à launch_component, mais la fonction ne lit jamais $args : elle détermine la sous-commande roadied à partir de $name seul et ajoute --yes en dur pour le tiler. La partie ':run-tiler --yes', ':run-rail', etc. est donc du code mort.
Scénario : Lire scripts/start-modular complet : $args est déclaré (local args="$2") mais aucune ligne du reste de la fonction ne l'utilise. Le suffixe ':run-tiler --yes' de chaque entrée de COMPONENTS n'a aucun effet.
Impact : Aucun impact fonctionnel. Les entrées COMPONENTS portent des valeurs fantômes qui ne correspondent à aucune sous-commande roadied valide ('run-tiler' n'existe pas) et pourraient induire en erreur un mainteneur qui tenterait de les modifier.

```
  local name="$1"
  local args="$2"
  local session="roadie-${name}"
```

Correction : Supprimer la partie ':args' des entrées COMPONENTS et le paramètre $args de la signature de launch_component. Conserver uniquement le nom du composant.
Validation : Vérifier la liste et les arguments avec une doublure de tmux dans les tests shell. Ne pas lancer les composants réels pour vérifier cette simplification.
Effort : XS. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/start-modular:103 — Boucle d'appel : name et args extraits, args ignoré

### MIN-008 — LOW — La sélection géométrique d’un écran ne change pas le résultat de conversion

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RoadieScreenCoordinate.swift:25
Statut : confirmé par lecture et sonde Swift pure exécutée (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/probe.log).
Description : Les deux fonctions screenMapping construisent des cadres dérivés de primaryHeight, puis cherchent un écran. Dans les formules finales, le décalage de cet écran s’annule. Pour toute géométrie normale d’écran, le résultat dépend seulement de primaryHeight et du point ou rectangle. Le choix par inclusion, intersection et recouvrement horizontal n’ajoute donc aucun comportement utile. Aucune justification spécifique n’a été trouvée dans les commentaires ni dans la spécification, le plan et les références de la fonction consultés. La simplification vaut aussi pour un écran au-dessus du principal : H=600, écran secondaire y=600 hauteur=800 et point global y=700 donnent yAX=-100, avec ou sans sélection. Les coordonnées NS restent globales ; il ne s’agit pas de coordonnées locales à chaque écran.
Scénario : Poser H=primaryHeight et S=mapping.nsFrame.maxY. axFrame.minY=H-S. La sortie y devient S-(rect.minY-(H-S))-rect.height = H-rect.minY-rect.height, quel que soit l’écran retenu. Pour un point, axFrame.maxY=H-nsFrame.minY, donc y=H-point.y. Ces résultats sont aussi exactement ceux des branches de repli sans écran.
Impact : Deux sélecteurs, un type intermédiaire et deux helpers CGRect augmentent le code à comprendre pour une simple inversion verticale. Ils allouent et parcourent une liste d’écrans à chaque conversion. Aucun gain chiffré de latence n’est revendiqué.

```
        let localTop = rect.minY - mapping.axFrame.minY
        return CGRect(
            x: rect.minX,
            y: mapping.nsFrame.maxY - localTop - rect.height,
            width: rect.width,
            height: rect.height
        )
```

Correction : Réduire les deux conversions aux formules globales, puis supprimer ScreenMapping, screenMapping et les helpers CGRect privés devenus inutiles. Éviter aussi de construire screenFrames dans les deux wrappers de production. Conserver les cas de test multiécrans.
Validation : Conserver les trois tests de RoadieScreenCoordinateTests et ajouter des rectangles à cheval sur deux écrans, hors écran et avec une liste vide. Vérifier l’équivalence sur des cadres d’écran valides. Aucun test exécuté ici. Si un comportement réel différent apparaît, rétablir les fonctions actuelles avant de poursuivre la simplification. Les tests existants lus couvrent le point d’un écran secondaire situé au-dessus du principal (RoadieScreenCoordinateTests.swift:20-33), ainsi que le retour AX vers NS (lignes 36-46).
Effort : XS. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RoadieScreenCoordinate.swift:50 — La conversion de cadre d’écran est axFrame.y = primaryHeight - frame.maxY.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RoadieScreenCoordinate.swift:62 — Même définition pour le sélecteur de rectangle.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DropPreviewController.swift:729 — Une autre conversion déjà utilisée dans le dépôt applique directement les mêmes deux formules, sans sélection d’écran.

Exemple de correction proposé, non appliqué :

```
static func nsPointToAX(_ point: CGPoint, screenFrames _: [CGRect], primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: primaryHeight - point.y)
}

static func axRectToNS(_ rect: CGRect, screenFrames _: [CGRect], primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryHeight - rect.minY - rect.height, width: rect.width, height: rect.height)
}
```

### REL-047 — LOW — Le replay de molette abandonne la position et les modificateurs enregistrés

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:412
Statut : perte des champs confirmée par lecture ; routage CGEvent réel non exécuté.
Description : macroTapCallback stocke point et modifiers pour scrollWheel. Le lecteur .scroll ne lit que scrollDeltaY. Il ne renseigne ni location ni flags sur l’événement construit. Une macro composée uniquement de défilement dépend donc de la position et des modificateurs du bureau au moment du replay, et non des valeurs capturées.
Scénario : Activer record et replay, avec include_mouse_moves=false. Enregistrer seulement un défilement sur la fenêtre A ; pour le cas des modificateurs, maintenir Maj pendant ce défilement. Déplacer ensuite le pointeur sur une fenêtre B et relâcher Maj avant roadie record replay NAME. La branche .scroll ne réapplique aucune des deux valeurs enregistrées. Une sonde à postEvent permet de vérifier directement que location et flags ne correspondent pas aux valeurs de TargetMacroEvent.
Impact : Le défilement rejoué peut viser une autre zone et perdre la variante demandée par le modificateur. Chemin expérimental et ponctuel : sévérité LOW.

```
        case .scroll:
            guard let delta = event.scrollDeltaY else { return }
            if let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) {
                postEvent(scroll)
            }
```

Correction : Avant émission, affecter la position enregistrée et les flags enregistrés au CGEvent de molette. Préserver le comportement de compatibilité lorsque point est absent d’un ancien fichier.
Validation : Injecter postEvent, rejouer un scroll avec une position distinctive et maskShift, puis vérifier location, flags et delta du CGEvent reçu. Ajouter le cas de point absent. Valider séparément le routage réel de molette sur macOS.
Effort : XS. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:572 — Le capteur stocke point, modifiers et scrollDeltaY.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:294 — Le replay annonce changed=true sans détecter cette perte.

Exemple de correction proposé, non appliqué :

```
case .scroll:
    guard let delta = event.scrollDeltaY,
          let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
    if let point = event.point?.cgPoint { scroll.location = point }
    scroll.flags = CGEventFlags(rawValue: event.modifiers)
    postEvent(scroll)
```

### REL-048 — LOW — La grille récursive affiche un niveau qui ne peut pas être activé

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetOverlayPresenter.swift:543
Statut : confirmé par lecture et sonde Swift pure exécutée (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/probe.log).
Description : La branche recursive ajoute une lettre sans borner path à maxDepth. cells accepte parentPath de longueur maxDepth puis crée des chemins de longueur maxDepth+1. Ces cellules sont affichées mais frame(for:) refuse ensuite leur chemin. Après leur sélection, l’overlay devient vide et la confirmation renvoie unknown_grid_path.
Scénario : Activer experimental.target_grid.enabled=true et garder mode="recursive", max_depth=3, grille 3x3. Ouvrir roadie grid interactive sur un grand écran. Taper quatre fois A : après la troisième frappe, les neuf cellules de profondeur 4 sont encore montrées ; la quatrième les sélectionne puis vide la grille. Appuyer Espace : perform refuse AAAA avec unknown_grid_path. Une reproduction pure consiste à demander cells(parentPath:"AAA",maxDepth:3), puis cell(path:leCheminRenvoyé,maxDepth:3) : le premier renvoie des cellules et le second nil.
Impact : L’utilisateur choisit une cellule affichée mais ne peut pas cliquer dessus. Retour arrière ou réinitialisation permet de récupérer. Chemin expérimental, sévérité LOW.

```
        case .characters(let value):
            guard let label = value.uppercased().first.map(String.init),
                  labels.contains(label)
            else { return }
            markActivity()
            path += label
            if config.mode == .autoClick && path.count >= config.maxDepth {
                finishActivating(path)
            } else {
                show(path: path)
                wakeMouseIfNeeded()
```

Correction : Ne jamais produire d’enfant au-delà de maxDepth. En mode recursive, bloquer la saisie d’une nouvelle subdivision à la profondeur maximale et garder la cellule courante visible et activable par Espace.
Validation : Test pur de cohérence : tout chemin rendu par cells doit être accepté par cell avec la même configuration. Tester le niveau maxDepth-1 puis maxDepth. Tester la session recursive : la frappe supplémentaire ne change pas path et Espace active la dernière cellule valide.
Effort : S. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetGridService.swift:274 — Le parent est accepté si sa profondeur égale maxDepth.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetGridService.swift:289 — Chaque cellule ajoute encore une lettre au chemin accepté.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetGridService.swift:355 — L’activation refuse path.count > maxDepth.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetGridService.swift:225 — La confirmation du chemin trop profond renvoie unknown_grid_path.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:751 — Le mode par défaut est recursive, maxDepth vaut 3 à la ligne 762.

Exemple de correction proposé, non appliqué :

```
// Au début de cells :
guard parentPath.count < maxDepth else { return [] }
// Avant path += label dans la session :
guard path.count < config.maxDepth else { return }
// Dans show : à maxDepth, afficher la cellule courante avec un état terminal
// sans labels de subdivision ; conserver la confirmation du chemin courant.
```

### REL-050 — LOW — Le démarrage peut être annoncé en échec avant la fin de son initialisation

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/start:79
Statut : plausible : délai fixe confirmé ; démarrage lent non reproduit.
Description : scripts/start attend exactement 1 seconde après le lancement du daemon puis teste le fichier pid. Si la machine est lente ou sous charge (CI, accès disque lent), le daemon peut ne pas avoir encore écrit roadied.pid et la vérification signale une erreur alors que le daemon démarre correctement. scripts/roadiedctl start utilise pour le même rôle une boucle de sondage de 30 × 0,1 s avec critère de convergence pid = verrou.
Scénario : Lancer 'make dev-start' sur une machine à disque lent ou avec charge CPU élevée. Le daemon démarre mais n'a pas encore écrit roadied.pid après 1 s. Le script retourne exit 1 avec un message d'erreur trompeur, alors que le daemon continue de s'initialiser.
Impact : Rapport d'échec de démarrage trompeur lors de 'make dev-start'. L'utilisateur peut relancer inutilement alors que le daemon tourne déjà.

```
# Le daemon écrit lui-même roadied.pid après avoir pris le verrou d'instance.
sleep 1
pid="$(cat "$pidfile" 2>/dev/null || true)"
if [[ -z "$pid" ]] || ! ps -p "$pid" >/dev/null 2>&1; then
  echo "roadied failed to start; logs: $log_dir/roadied.stderr.log" >&2
  exit 1
fi
```

Correction : Sonder le PID et le verrou avec un délai borné configurable, puis annoncer explicitement une absence de disponibilité dans ce délai. Ne pas annoncer avec certitude un échec du processus encore vivant.
Validation : Ajouter un test shell avec faux daemon et écriture du PID retardée. Vérifier succès après convergence et message de délai dépassé si le processus reste en initialisation. Ne pas lancer le vrai daemon pour ce test.
Effort : S. Risque : LOW.
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/roadiedctl:58 — Boucle de sondage 30 × 0,1 s utilisée dans start_roadied

## Complexité algorithmique et performance

PERF-010 : reconstruction O(w²) par scans de suppression répétés ; construire les appartenances en une passe. PERF-011 : O(k×n²), donc O(n³) si k≈n ; dédupliquer les scopes avant validation pour revenir à une validation O(n²) par scope. PERF-012 : première passe O(m×w log w), puis O(m×w) répété pour les membres orphelins ; exclure une fois les candidats déjà revendiqués et chercher les deux meilleurs sans tri. Cette dernière correction ne garantit pas O(M+W) pour les groupes homonymes non résolus. Aucune borne effective ni choix de coût documenté ne neutralise ces chemins fréquents. Trois contre-audits indépendants confirment le niveau HIGH.
Aucune latence utilisateur mesurée. Les classes de coût proviennent des parcours réels. Chaque correction doit conserver résultats et ordre, puis comparer les mêmes entrées avant/après. Revenir au code précédent si les invariants régressent.

## Minimalisme & Frugalité

Potentiel minimalisme : ~63 lignes suppressibles à comportement constant
MIN-006 : 3 lignes inaccessibles. MIN-007 : ~2 lignes de paramètre/extraction inutiles, plus simplification des six entrées. MIN-008 : ~58 lignes de sélection d’écran algébriquement redondantes. Estimation indicative, sans modification du source.
Checklist : helpers, wrappers, état dérivé, branches mortes, abstractions anticipées, dépendances, code hors besoin. Pas de framework proposé pour les corrections.

## Vertus LLM & Responsabilité Future

Les résultats explicites et les transactions réduisent les règles implicites. Les tests de pannes rendent les invariants plus lisibles. Leur application reste incomplète aux chemins signalés. Le volume de correction répond aux scénarios précis, mais le vert des tests ne suffit pas à certifier les autres appelants. Aucune origine du code n’est déduite de son style. Pas d’intégration LLM détectée dans Roadie.

## Points positifs

- Sources/RoadieDaemon/LayoutCommandService.swift:468 : commitStageTransfer fournit un rollback atomique complet (état avant/après capturés, vérification d'égalité) pour tout transfert de scope, avec propagation de PartialCommitError si le retour arrière lui-même échoue.
- Sources/RoadieDaemon/LayoutCommandService.swift:351 : applyAfterIntent écrit l'intent avant l'effet AX, met à jour les frames réelles après succès partiel et restaure l'intent précédent si tous les cadres sont refusés — la commande ne laisse jamais d'état incohérent.
- Sources/RoadieDaemon/CLICommandRouter.swift:326 : windowID refuse value == 0 avec une précondition explicite dans le commentaire (REL-001), prévenant l'erreur fatale Swift pour stage summon 0 et les commandes group.
- Sources/RoadieDaemon/StageCommands.swift:1710 : nextGeneratedStageID documente la contrainte par un commentaire précis (REL-001) et gère proprement le fallback UUID sans boucle infinie (UUID.uuidString est non numérique, donc non conflit avec les identifiants numériques).
- BSPLayoutStrategy.splitRatio retourne O(1) pour le cas sans priorité (PERF-008) : garde ajoutée avant tout parcours de sous-liste. Commentaire documente le compromis restant pour le chemin prioritaire.
- BSPLayoutStrategy applique maintenant BSPTree.gap(for:in:innerGap:) dans splitHorizontally et splitVertically (REL-033) : les tuiles restent dans le conteneur même avec un gap démesuré, en réutilisant la fonction déjà présente dans BSPTree.
- TilingConfig lève une erreur de décodage explicite pour toute valeur default_strategy inconnue (REL-034) : le repli silencieux vers .bsp est remplacé par un message lisible qui identifie la valeur fautive et les valeurs attendues.
- LayoutRequest porte maintenant masterRatio et MasterStackLayoutStrategy l'utilise (REL-030) : les nouvelles fenêtres sont exclues des candidats de ratio pour éviter l'héritage d'une taille arbitraire macOS.
- validateTargetGrid et validateAppTargets ne contiennent plus de branches inatteignables (MIN-003, MIN-005) : les bornes sont appliquées dans les initialiseurs ; la validation ne redouble pas ce travail.
- SpatialBSPLayoutStrategy utilise Set pour les feuilles connues (PERF-002) : O(n) pour le chemin normal, sans contains récursif par fenêtre.
- BSPTree.gap(for:in:innerGap:) centralise la borne de l'espacement pour tous les modes BSP (REL-031, REL-033) : la constante minimumChildExtent est alignée avec minimumTileExtent de MasterStackLayoutStrategy.
- decodeFlexibleDouble propage les erreurs pour les types incorrects (REL-011) : un booléen ou une chaîne provoque maintenant une erreur explicite au lieu d'un repli silencieux sur nil.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:325 — les identifiants de fenêtre de la CLI exigent une valeur strictement positive.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:312 — le code de sortie dépend du statut explicite du résultat.
- REL-005 : applyPersistedMetadata (DaemonSnapshot.swift:582) couvre les quatre sous-cas en un seul passage O(s + d·l) : noms et modes des stages existantes, création des stages vides persistées, restauration des stages actives des desktops non courants, propagation des labels. AutomationSnapshotService.stageSnapshots lit le RoadieState enrichi sans code supplémentaire.
- REL-035 + REL-036 (tour 4) : les deux correctifs sont défensifs par construction — round-trip check avant écriture atomique pour REL-035, fichier seul comme source de vérité pour REL-036 — ce qui rend les régressions silencieuses impossibles sans faire échouer le code entourant.
- StateAudit.swift:228-232 : le commentaire de repairScopes documente explicitement la politique de grâce des membres absents, la déduplication indépendante de la visibilité et le comportement sur anciens fichiers sans PID, ce qui servira de référence pour de futurs tests de régression.
- {"module": "03", "text": "scripts/stop valide le PID et l'exécutable avant d'envoyer SIGTERM à un composant modulaire. Un PID réutilisé par un autre programme ne peut pas être tué par mégarde.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/stop", "line": 94, "note": "is_roadied_executable vérifié avant kill -TERM"}}
- {"module": "03", "text": "scripts/test n'exporte plus de HOME temporaire vers with-xcode via exec ; le shell parent nettoie le répertoire dans tous les cas (succès et échec).", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/test", "line": 9, "note": "trap cleanup EXIT + appel sans exec"}}
- {"module": "03", "text": "La seule dépendance Swift tierce (TOMLKit 0.6.0) est verrouillée sur une révision exacte (ec6198d37d495efc6acd4dffbd262cdca7ff9b3f) dans Package.resolved. Aucune autre dépendance réseau déclarée.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Package.resolved", "line": 9, "note": "revision fixée, version 3 du format"}}
- {"module": "03", "text": "removeReporting dans FileAdministration émet un diagnostic sur stderr en cas d'échec de suppression — les faux positifs de nettoyage (OBS-003) sont éliminés et l'erreur reste observable.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift", "line": 232, "note": "fputs(\"roadie: cleanup failed for ...\", stderr)"}}
- Tour4 : frontmostWindowCandidates retourne une erreur explicite (no_focused_window) quand la fenêtre focalisée ne peut pas être associée à un CGWindowID. Il est impossible de cliquer avec une identité ambiguë (AppTargetQueryService.swift:436-440).
- Double protection REL-037 : les stages d'autres bureaux ne reçoivent que [.inspect] à la liste (TargetHintService.swift:632) et refusedOutsideCurrentDesktop bloque l'activation directe même si une cible est construite manuellement avec un autre desktopId (TargetHintService.swift:507-514).
- Le defer de relâchement REL-038 est aussi correct pour les séquences équilibrées : held est vide après un down/up normal, donc aucun relâchement fantôme n'est émis (TargetMacroService.swift:320-325, vérifié par Audit022R4LotT4Tests.swift:151).
- Les cibles de la portée visible_windows portent le windowID de leur fenêtre depuis audit02 (AppTargetQueryService.swift:511) ; visibleWindowsCandidates bénéficie ainsi de la même vérification de focus que frontmost_window (AppTargetQueryService.swift:813).
- REL-039 : persistentReorderPosition calcule le rang sur l'ordre complet (orderedStageIDs) incluant les stages vides, évitant le glisser silencieusement sans effet : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:410.
- REL-040 : la transformation affine parallax est définie une seule fois et partagée entre dessin et test du clic ; l'inverse est correctement appliqué au point ; le déterminant est borné à xScale >= 0.45 pour garantir l'inversibilité : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCardView.swift:587.
- PERF-003 : géométrie du dépôt commune et linéaire, avec test de comparaison contre la version récursive à plusieurs tailles : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DropPreviewController.swift:488.
- Le menu désactivé évite tout snapshot ; les trois familles partagent exécution et journal : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TitlebarContextMenuController.swift:209 et :490.
- Le panneau de bordure consomme un modèle testable réellement produit par refresh ; la pastille est bornée : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/BorderController.swift:85 et :225.
- Les dix IDs assignés sont résolus après tour4 sans introducing de nouvelles régressions dans le périmètre UI/rail/drag.
- DisplayParkingService.swift:257-294 : la restauration regroupe bien par bureau d’origine ; REL-017 confirmé résolu après lecture intégrale actuelle.
- JSONPersistence.swift:125-151 : mutateChecked refuse l’exécution du corps si verrou ou décodage échoue, puis propage tout échec d’écriture ; cause racine résiduelle dans les appelants multi-écritures, pas dans cette primitive.
- FileLock.swift:82-94 : withLock libère le verrou par defer ; les usages JSONPersistence ont une libération explicite même sur erreur.
- LayoutCommandService.swift:468-500 : commitStageTransfer conserve avant/après, restaure conditionnellement et expose PartialCommitError en cas d’échec du rollback ; sa réutilisation sur treeCommand évite une nouvelle abstraction.
- WindowGroupCommandTests.swift : la lecture intégrale confirme les assertions sur membres et focus persistés (TEST-003 résolu). Le manque de vérification de statut sur membre absent explique CMD-NEW-01 sans réouvrir TEST-003.
- RestoreSafetyService.swift : lecture intégrale des exclusions plein écran natif, des fenêtres introuvables, du marqueur de reprise, de la réservation sous verrou puis des opérations AX hors verrou.
- Tous les fichiers Core/Stages qui manquaient à la première lecture ont été lus intégralement dans leur version actuelle.
- AutomationSnapshot porte les identifiants écran/bureau nécessaires aux stages et groupes ; compatibilité des anciens JSON assurée par les champs optionnels.
- Les clés de configuration et les types erronés sont contrôlés ; les modèles n’exécutent ni processus ni requête réseau.
- La normalisation des limites des configurations de ciblage borne les volumes AX, la profondeur, le nombre de cellules et les événements enregistrés.
- PERF-009 : index unique des refus construit à LayoutMaintainer.swift:2751 et consommé par lookup à 2787 ; lecture directe du helper à 2864.
- REL-035 : la comparaison des règles relues à WindowRuleAffinityService.swift:156 précède tout remplacement du fichier de règles.
- REL-005 : la fusion de métadonnées à DaemonSnapshot.swift:582 préserve les stages vides et leurs modes sans remplacer les fenêtres runtime.
- {"module": "06", "text": "ProcessLiveness.isAlive traite pid ≤ 0 avant kill(0), évitant tout envoi de signal à un groupe de processus.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/ProcessLiveness.swift", "line": 7, "note": "guard pid > 0 avant kill(pid, 0)"}}
- {"module": "08", "text": "TreeDumpService.dump construit un dictionnaire liveWindowsByID hors de la boucle des scopes, évitant les recherches O(n) dans la boucle.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TreeDump.swift", "line": 80, "note": "Dictionary(uniqueKeysWithValues:) avant les boucles imbriquées"}}
- {"module": "06", "text": "ShutdownRegistry garantit l'idempotence par un booléen didShutdown : signaux multiples simultanés ne déclenchent les actions qu'une seule fois.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/roadied/main.swift", "line": 108, "note": "guard !didShutdown avant l'exécution des actions"}}
- {"module": "03", "text": "Package.swift ne déclare qu'une seule dépendance tierce (TOMLKit) avec un identifiant de révision exact dans Package.resolved ; la surface d'attaque de la chaîne d'approvisionnement est minimale.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Package.swift", "line": 19, "note": "Unique entrée .package, cohérente avec Package.resolved"}}
- {"module": "03", "text": "scripts/install extrait l'identité de signature de l'application déjà installée pour maintenir la continuité des permissions Accessibility macOS, en utilisant le hash de certificat si disponible.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/install", "line": 27, "note": "codesign --display --verbose=4 -r- puis extraction H\"<hash>\" en priorité"}}
- {"module": "06", "text": "scripts/start-modular documente explicitement la contrainte de cohérence avec modular_components de scripts/stop (REL-032) via un commentaire dans le tableau COMPONENTS.", "evidence": {"file": "/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/start-modular", "line": 47, "note": "Commentaire 'Tout composant ajouté ici doit aussi figurer dans modular_components de scripts/stop'"}}
- Les 16 fichiers production assignés ont été relus intégralement à HEAD, soit 7 512 lignes. DisplayCommands.swift a aussi été lu intégralement pour suivre la conversion des résultats.
- Identité de fenêtre, confirmation du focus et contrôle de géométrie précèdent désormais tous les clics applicatifs de ces flux.
- Le replay équilibre les touches et boutons restés ouverts ; les clics sémantiques remplacent une paire complète et les combinaisons non représentables restent brutes.
- Les callbacks AX tournent sur le MainActor ; les caches et registres utilisés par plusieurs fils protègent leur état par verrou. Le lot de scans parallèles réserve une case distincte par fenêtre.
- Les listes de cibles indexent fenêtres et écrans. La recherche conserve au plus 500 cibles et fusionne les lots triés. Les boucles d’occlusion portent leur complexité dans le code.
- RailRuntimeStateStore.mutate renvoie nil en cas d’erreur de persistance et écrit le diagnostic sur stderr ; les setters de commandes exposent ce résultat (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailRuntimeState.swift:85-94).
- RailFileWatcher ne ferme le descripteur que dans le cancel handler et écarte les événements d’une ancienne source (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailFileWatchers.swift:30-44).
- RailThumbnailStore limite les captures concurrentes à un lot et à un budget explicite ; les vignettes sont réduites et le test de vide échantillonne 32×32 pixels (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailThumbnailStore.swift:65-82, 127-130, 193-197).
- RailSettings met en cache les lectures réussies par chemin et signature, avec accès au cache sous NSLock (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailSettings.swift:124-135, 495-510).
- Complexité algorithmique : les neuf fichiers complémentaires ont été vérifiés. Pas de boucle quadratique, N+1 persistant, tri imbriqué ou copie en cascade démontré. Le tri de demandes de capture est O(m log m), documenté. UI-NEW-003 porte sur des calculs géométriques inutiles et non sur un défaut quadratique.

## Dépendances et sécurité

TOMLKit est verrouillée à une révision. Aucun scan externe de vulnérabilités, aucune conclusion d’absence de CVE. Socket Unix et processus locaux relus. Pas d’API web, paiement ni SQL applicable. Deux scans des chemins sensibles. Les permissions réelles du HOME et les protections système contre les liens symboliques ne sont pas certifiées.

## Findings supprimés par la baseline

Aucun. Les candidats réfutés ou non retenus sont documentés séparément et ne sont pas des risques acceptés.

## Roadmap de remédiation

1. Corriger les HIGH de complexité et valider leurs invariants par tests de tailles croissantes.
2. Terminer REL-021 et les adaptations des statuts de résultat. Ajouter les cas métier absents.
3. Traiter les LOW sans refonte générale.

## Ce qui n’a pas été vérifié

- 47 des 1163 tests annoncés n’ont pas été exécutés : 42 tests des suites CLICommandRouterTests, Audit022LotITests et Audit022R2LotCTests utilisent des sockets hors du scratch ; 5 tests de cycle de vie dans Audit022R4LotT6Tests arrêtent leurs propres processus. Le test réseau intermittent cité fait partie des exclusions.
- Aucune interaction réelle avec les fenêtres, clics, glisser-déposer, hotkeys, écrans, Accessibilité macOS ou capture. Les scénarios système restent vérifiés par lecture ; les sondes ajoutées sont pures.
- Aucun démarrage, arrêt ou redémarrage de daemon/composant/application. Scripts d’installation, signature, désinstallation et cycle de vie seulement lus. Aucun make install.
- Aucun profil CPU/mémoire ni benchmark de latence. Les coûts algorithmiques sont établis par les boucles et leurs appelants, sans revendication de durée observée.
- Aucun scan externe CVE, audit exhaustif du code de TOMLKit ni scan complet des secrets dans l’historique Git. Permissions réelles du HOME, précréation de chemins et protections système contre les liens symboliques non certifiées.
- Les 96 fichiers Swift de production sont lus intégralement. Tests, scripts, documentation, specs et ressources sont contrôlés selon les risques. Aucun taux instrumenté de couverture de tests, mutation testing ou taux global de duplication calculé.
- La course interprocessus de REL-046 et le démarrage lent de REL-050 n’ont pas été reproduits ; ils restent plausibles.
- Le pointeur audits/latest et les artefacts des audits précédents restent inchangés, conformément au périmètre d’écriture autorisé.
- Les exemples de correction du rapport n’ont pas été appliqués ni compilés. Seules les sondes de comportement courant ont été compilées et exécutées.

## Intégrité et artefacts

Aucun code source modifié. Aucun commit, stash, checkout ou reset. Contrôle : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/integrity-check.json
Validation canonique : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/validation/session-validator.log
Comparaison : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/comparison.json
Candidats arbitrés : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/deferred-and-merged.json
Rapport : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-03/scoring.md
