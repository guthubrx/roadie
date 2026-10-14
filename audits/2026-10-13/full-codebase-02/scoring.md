# Audit de code Roadie — v14 après corrections

**Date :** 2026-10-13. **Mode :** readonly, périmètre complet, un cycle.
**Racine :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation
**Branche :** 022-audit-remediation. **Commit :** 4766213e1a00b7d96e1ba959d1b0b277863a4939. 34 commits au-dessus de main.
**Score global : A — 93.21/100. Blocage de livraison : OUI.**
**Durée :** 20.2 minutes. **Constats actifs :** 19 (3 HIGH, 10 MEDIUM, 6 LOW).

## Résumé exécutif

Les 50 constats initiaux ont été vérifiés : **46 résolus, 4 partiels, 0 ouvert sans progrès**. 15 nouveaux constats s’ajoutent aux quatre résiduels. « Nouveau » signifie absent du premier rapport ; cela ne prouve pas une régression introduite par cette session.
Les six anciens HIGH autres que REL-001 sont résolus. REL-001 reste HIGH avec deux autres entrées fatales. Deux nouveaux HIGH de complexité maintiennent aussi le blocage v14. Aucun CRITICAL.
La note A est une moyenne pondérée. **La fiabilité reste D (57/100)** ; elle ne doit pas être masquée par la moyenne.

## Tendance

| Domaine | Avant | Maintenant | Écart de score |
|---|---:|---:|---:|
| Global | B+ 83,16 | A 93.21 | +10.05 |
| security | A 100 | A 100 | 0 |
| supply_chain | A 100 | A 100 | 0 |
| observability | A 97 | A 98 | 1 |
| reliability | F 0 | D 57 | 57 |
| tests | A- 88 | A 100 | 12 |
| performance | A 97 | A 100 | 3 |
| complexity | D 56 | B+ 80 | 24 |
| quality | A 99 | A 100 | 1 |
| architecture | A 100 | A 100 | 0 |
| ai_hygiene | A 100 | A 100 | 0 |
| duplication | A 97 | A 100 | 3 |
| minimalism | A 94 | A 99 | 5 |
| ux | A 100 | A 100 | 0 |
| llm_security | N/A  | N/A  | N/A |

Méthode identique au premier audit : domaine = 100 − 25×CRITICAL − 10×HIGH − 3×MEDIUM − LOW, plancher zéro. Moyenne pondérée des domaines applicables (somme des poids : 19). Les constats algorithmiques vont dans complexity et ne sont pas comptés une seconde fois dans performance. Les HIGH bloquent indépendamment de la moyenne. Aucune suppression par baseline (fichier absent).

## Périmètre et vérifications

Lecture intégrale des 96 fichiers Swift de production; tests, scripts, docs et specs par risque. La couverture de lecture ne mesure pas la couverture des tests.
Inventaire : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/read-inventory.json
Compilation via swift test réussie. **1044 tests passés**, 42 exclus de trois suites pour respecter les chemins autorisés. Le total de 1086 annoncé par la session n’est donc pas présenté comme réexécuté intégralement ici.
Journal : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/validation/test.log
Sondes réelles isolées : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/validation/probe-results.log
Les sondes confirment le faux code de sortie, le débordement de géométrie bsp, la suspension après release et la lecture UTF-8 vide. Elles confirment aussi l’acceptation de StageID Int.max et le dépassement suivant sans provoquer le trap.
Le dossier temporaire /tmp/roadie-build-022-audit2 a été supprimé. Preuve : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/validation/cleanup.json

## Tableau des 50 constats d’origine

| ID | Sévérité initiale | Constat | Statut actuel | Preuve actuelle |
|---|---|---|---|---|
| REL-001 | HIGH | Des arguments stage invalides peuvent arrêter le daemon | **partiel** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageStore.swift:1153 — Les deux scénarios initiaux sont corrigés : reorder borne avant soustraction, et les entrées publiques contrôlent les identifiants vides. Un autre argument stage provoque encore un dépassement fatal : une stage nommée Int.max mène à Int.max + 1 lors de assign-empty. Voir REL-001. Deux chemins fatals restent ouverts : génération après Int.max et stage summon 0. |
| REL-002 | HIGH | La réparation efface les associations des fenêtres encore ouvertes mais invisibles | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StateAudit.swift:237 — La réparation ne retire plus un membre absent qu’avec un PID connu et déclaré mort. La déduplication reste indépendante de la visibilité. La grâce de réconciliation de 30 minutes reste la politique générale du snapshot ; elle n’est pas une nouvelle preuve de fermeture. |
| REL-003 | HIGH | Le mode lettres réinterprète la lettre dans une autre liste | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetModeRuntimeController.swift:255 — La fermeture résout désormais la lettre dans overlay.report.targets, puis transmet exactement la cible conservée à activate(target:action:). |
| PERF-001 | HIGH | La validation des trous de disposition parcourt les fenêtres dans chaque cellule | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1794 — La recherche parmi tous les cadres pour chaque cellule a disparu. Les intervalles de centres sont calculés une fois ; chaque colonne cumule les intervalles de lignes dans un tableau de différences. Complexité O(n²), mémoire O(n), au lieu de O(n³). Aucun gain de latence mesuré dans cette revue. |
| PERF-002 | HIGH | Le plan BSP normal reparcourt tout l'arbre pour chaque fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift:28 — Le chemin normal spatialBsp utilise un Set de feuilles, sans contains récursif par fenêtre. BSPTree.windowIDs remplit un accumulateur unique. La réconciliation amont retire les feuilles en un passage et utilise aussi un Set. Les insertions de secours restent un chemin distinct explicitement documenté. |
| PERF-003 | HIGH | La géométrie de groupe copie et fusionne des suffixes en O(n²) pendant le glisser | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DropPreviewController.swift:488 — Les deux appelants utilisent DropGroupGeometry.planGroup. Une boucle remplit un seul dictionnaire, sans copie de suffixe ni fusion récursive : O(n). Le calcul de structuralPlacements utilise aussi un Set pour le groupe cible. |
| PERF-004 | HIGH | La réparation de voisinage refait une recherche linéaire pour chaque fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:2689 — L’intersection de la stage et des voisines utilise un Set construit une seule fois. Le filtre conserve l’ordre initial de la stage et devient O(n+m). Un autre parcours répété, distinct, est signalé dans PERF-009. |
| REL-004 | MEDIUM | La grille écran ignore le changement de moniteur demandé par les flèches | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetModeRuntimeController.swift:348 — Affichage et activation utilisent la même fermeture rootFor ; un index différent de celui de la racine figée résout le nouvel écran. |
| REL-005 | MEDIUM | Le snapshot d’automatisation perd les noms et les stages vides persistées | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:564 — La réconciliation fusionne les stages persistées, même vides, avec leur nom et leur mode. Elle reporte les labels des desktops et l’activeStageID des desktops non courants. Les modes des stages runtime déjà créées sont aussi mis à jour ; les décisions de focus du desktop courant sont conservées. |
| REL-006 | MEDIUM | Le tri spatial utilise une relation non transitive | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:2116 — Le comparateur dépend désormais de clés de bandes calculées avant le tri, puis de l’ID. Il n’alterne plus les axes selon chaque paire. Les permutations du triplet initial conduisent au même ordre. |
| REL-007 | MEDIUM | Les règles de placement ignorent le rôle AX de la fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:1882 — Le contexte de placement reçoit role et subrole depuis la fenêtre AX. Il reçoit aussi une classification flottante explicite : hors mosaïque, épinglée ou stage float ; une candidate en attente d’écran conserve nil. |
| REL-008 | MEDIUM | Une règle différée faute d’écran cible n’est jamais retentée | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:1892 — Le résultat de placement distingue placed, deferred et settled. Une destination indisponible provoque continue avant l’insertion dans observedRulePlacementWindowIDs. La fenêtre reste donc retentable après retour de l’écran. |
| REL-009 | MEDIUM | Les placements de plusieurs écrans empêchent de sauver leurs dispositions | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:3135 — La fusion des résultats d’écriture ne parcourt que les IDs de la stage courante. Les résultats des autres écrans ne polluent plus placements avant la garde d’égalité. |
| DUP-001 | MEDIUM | Le menu recopie trois fois l’exécution et le journal d’une action | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TitlebarContextMenuController.swift:481 — Les trois familles de menus appellent actionTarget, qui délègue à une seule méthode executeAndLog. La construction des destinations reste distincte. |
| MIN-001 | MEDIUM | Le rail recopie des helpers disponibles et conserve un double adaptateur de menu | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:373 — RailPanel réutilise stageCard pour les actions et les charges de glisser. StageCardView partage les cadres de mosaïque/icônes entre rendu et sélection. Le double adaptateur de renommage a disparu. Le nouveau défaut parallax concerne une transformation graphique et ne réouvre pas la duplication initiale. |
| OBS-001 | MEDIUM | La rotation des logs ouverts coupe leur consultation courante | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift:129 — La rotation de stdout/stderr conserve l’inode : copie vers .1 puis troncature du fichier courant. La copie doit réussir avant la troncature; applied reflète son résultat. La perte possible entre copie et troncature est explicitement documentée. |
| PERF-005 | MEDIUM | Les commandes répètent des recherches linéaires évitables | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1553 — Les trois recherches répétées citées sont supprimées. Le classement des stages partitionne sur members.isEmpty; normalizedOrder et applyPlan construisent leurs ensembles hors boucle. Les résultats restent ordonnés. |
| PERF-006 | MEDIUM | Le menu désactivé déclenche quand même un relevé complet à chaque clic droit | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TitlebarContextMenuController.swift:209 — La garde enabled précède snapshot et le reste du traitement. Les moniteurs restent installés pour le rechargement à chaud. |
| REL-010 | MEDIUM | Le focus annonce un succès lorsque AXRaise échoue sans délai dépassé | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieAX/SystemSnapshotProvider.swift:1072 — AXRaise doit réussir. Une erreur de mise au premier plan ou de fenêtre focalisée doit être compensée par une confirmation explicite de l’état réel. |
| REL-011 | MEDIUM | Les mauvais types numériques peuvent passer la validation puis devenir des défauts | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1611 — decodeFlexibleDouble ne confond plus type invalide et clé absente. Il propage la première erreur quand le repli entier échoue. load et validate utilisent ce décodage ; le rattrapage textuel ancien a disparu. |
| REL-012 | MEDIUM | Le clic part même si la fenêtre cible ne peut plus être focalisée | **partiel** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:426 — La portée visible_windows refuse désormais les fenêtres absentes/non focalisées et les éléments déplacés ou remplacés. La portée frontmost_window ne renseigne cependant aucun windowId : elle saute entièrement le contrôle de focus. Une fenêtre recouverte conserve son cadre et peut provoquer un clic sur la fenêtre de devant. |
| REL-013 | MEDIUM | La réponse stages ne précise pas l’écran de chaque stage | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AutomationSnapshotService.swift:103 — Chaque stage porte désormais displayId ; chaque groupe porte displayId et desktopId. Le contrat conserve le décodage des anciens JSON grâce à des champs optionnels. |
| REL-014 | MEDIUM | config reload annonce une application sans changer la configuration du daemon | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:296 — config reload appelle le ConfigReloadService partagé du daemon, publie activePath/config et maintient la configuration précédente en cas de validation refusée. Le cache des règles compare la liste des règles réellement actives, y compris après chargement d’un autre fichier. |
| REL-015 | MEDIUM | Le PID informatif ne prouve pas que le verrou du daemon est libre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift:223 — La CLI tient une réservation partagée avant ses sondes et pendant toute exécution locale. Le daemon prend cette réservation en exclusif avant son PID et ses composants. Le socket complète le PID informatif. Le script start conserve le PID d’un processus encore vivant. |
| REL-016 | MEDIUM | Déplacer une fenêtre vers son bureau actuel la masque | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DesktopCommands.swift:146 — Les deux entrées publiques refusent le bureau actuel. Le corps partagé ne masque que si le bureau cible est invisible. Il restaure explicitement une fenêtre garée sur un bureau affiché, y compris en mode float. |
| REL-017 | MEDIUM | La reconnexion d’un écran fusionne les stages de bureaux différents | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DisplayParkingService.swift:260 — Après reconnaissance de l’écran, la restauration partitionne les stages par origin.desktopID et construit un targetScope distinct par bureau. |
| REL-018 | MEDIUM | L’abonnement perd des événements lors du remplacement du journal | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/EventSubscriptionService.swift:99 — Le curseur associe décalage et inode; les générations sont ouvertes sous verrou partagé, identifiées sur leur descripteur, puis lues dans l’ordre avant le courant. Les inodes doublons sont écartés. Une génération disparue ou une troncature détectée émet events.gap, même hors des filtres. Les lignes partielles ne font pas avancer le curseur. |
| REL-019 | MEDIUM | Le focus souris sélectionne une fenêtre cachée derrière une autre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FocusFollowsMouseController.swift:261 — La première fenêtre à l’écran dans l’ordre du snapshot est choisie avant le filtre d’éligibilité. Une fenêtre non gérée masque donc les fenêtres derrière. Le focus et le départ du glisser partagent cette sélection. Le fournisseur conserve l’ordre CG et inclut les fenêtres non candidates. |
| REL-020 | MEDIUM | Un écran placé à gauche est confondu avec une ancienne zone de masquage | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/HiddenWindowPlacement.swift:38 — La détection historique des coordonnées négatives vérifie désormais l’absence d’intersection avec tous les écrans présents. La fenêtre visible sur un écran à gauche n’est plus exclue. |
| REL-021 | MEDIUM | Une mutation renvoie un succès métier après échec de persistance | **partiel** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/JSONPersistence.swift:86 — mutateChecked et les commandes contrôlées propagent les erreurs. Les tests de rail pin et de panne initiale sont utiles. Des commandes effectuent encore des écritures durables ou des effets AX avant une seconde persistance faillible, puis annoncent changed=false sans restaurer : zoomParent, transfert de bureau, transfert de fenêtre et de stage. Voir REL-021, à fusionner avec les occurrences StateAudit/UI collectées par le coordinateur. |
| REL-022 | MEDIUM | Le dépôt entre deux rails échoue si leurs stages portent le même identifiant | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailController.swift:776 — La garde compare maintenant le couple écran/stage. Deux stages de même identifiant sur des écrans distincts déclenchent le déplacement. |
| REL-023 | MEDIUM | Le déplacement --no-follow rend visible une stage inactive | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:664 — Une stage déplacée sans activation produit maintenant des frames de masquage. Les frames de retour sont recentrées sur le scope exact et seulement pour les membres transférés encore présents, ce qui couvre R1-14. |
| REL-024 | MEDIUM | Le replay avale le relâchement de souris si la cible AX est absente | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:327 — Le replay traite une paire down/up applicative comme un geste avant toute émission. Un échec sémantique retombe sur les événements bruts, dont le relâchement. Le nombre de replis apparaît dans la réponse. |
| REL-025 | MEDIUM | Les macros perdent le bouton droit et les modificateurs souris | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:527 — Le bouton est enregistré et les événements bruts conservent leurs drapeaux. Seuls clic gauche, droit ou Commande-clic sont sémantiques ; les combinaisons non représentables restent brutes. |
| REL-026 | MEDIUM | La commande width sélectionne toujours le premier écran | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WidthAdjustmentService.swift:40 — Le scope et l’écran sont dérivés de la fenêtre focalisée lorsqu’elle est une candidate de la stage active. Le repli sur le premier écran reste réservé à l’absence de cette fenêtre. |
| REL-027 | MEDIUM | Les ajustements relatifs utilisent la largeur de la première fenêtre | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WidthAdjustmentService.swift:68 — Le ratio de référence est celui de activeID, avant le calcul de nudge/preset. La règle pour allWindows utilise explicitement cette même fenêtre active. |
| REL-028 | MEDIUM | Focaliser une fenêtre temporairement absente efface son signet | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowBookmarkCommands.swift:64 — L’absence ponctuelle conserve le signet et produit un échec explicite. La suppression immédiate exige désormais un PID mémorisé dont le processus est mort. La purge différée conserve sa grâce. |
| REL-029 | MEDIUM | Enregistrer une affinité supprime les autres actions des règles générées | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleAffinityService.swift:181 — Le rendu réécrit désormais tous les champs d’action du modèle : manage, exclude, floating, layout, gap_override, scratchpad et emit_event, en plus des affectations et follow. Le défaut initial de suppression systématique de ces actions est corrigé. REL-035 relève un défaut distinct de conservation des valeurs chaîne. |
| REL-030 | MEDIUM | La configuration master_ratio n'arrive jamais au moteur de disposition | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/LayoutTypes.swift:79 — masterRatio fait partie de LayoutRequest, est transmis par les producteurs de layout et de réparation, puis utilisé par MasterStackLayoutStrategy. Les fenêtres nouvelles sont exclues de la géométrie à préserver ; les fenêtres existantes et les priorités conservent leur ratio manuel. |
| REL-031 | MEDIUM | Un espacement trop grand produit une fenêtre hors du conteneur | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/MasterStackLayoutStrategy.swift:30 — Le cas initial masterStack avec espacement 600 dans 1000×500 est corrigé par des espacements horizontal et vertical bornés. BSPTree dispose aussi de cette borne. Le mode historique bsp garde un défaut analogue distinct, enregistré comme REL-033. |
| REL-032 | MEDIUM | La désinstallation laisse une instance autonome active | **partiel** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/uninstall:30 — L’instance Roadie.app ou tmux monolithique est maintenant arrêtée par scripts/stop avant les suppressions. Le mode modulaire fourni par scripts/start-modular lance aussi cinq processus avec leurs propres PID. scripts/stop ne lit que roadied.pid ou daemon-status.json : ces composants restent actifs et la désinstallation poursuit ses suppressions. |
| TEST-001 | MEDIUM | Le test des requêtes vérifie seulement le nom recopié dans la réponse | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/QueryCommandTests.swift:52 — Les réponses sont décodées en types métier. Les tests vérifient les IDs, les scopes, les membres du groupe et les règles ; null ou un tableau vide ne passent plus. |
| TEST-002 | MEDIUM | Les tests de cibles ne couvrent pas le raccordement aux effets système | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/TargetModeRuntimeControllerTests.swift:103 — Le contrôleur est réellement instancié avec un présentateur espion. Ses fermetures de sélection et de clic sont appelées. Les adaptateurs de focus, de géométrie et d’émission souris sont testés avec erreurs et replis. Les frontières natives Carbon/AX/CGEvent restent à valider manuellement, limite explicite distincte de l’absence ancienne de tests de raccordement. |
| TEST-003 | MEDIUM | Le test des commandes de groupe ne contrôle que changed | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/WindowGroupCommandTests.swift:26 — Le test relit désormais les membres exacts et activeWindowID après create/add/focus/remove, puis l’absence du groupe après dissolve. Des tests séparés couvrent retrait du membre actif, dissolution sous deux membres, identifiants absents et déduplication. |
| TEST-004 | MEDIUM | Le test de l’indicateur de groupe ne couvre aucun rendu réellement utilisé | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/BorderController.swift:85 — refresh transmet groupLabel dans BorderRenderModel au panneau réel. BorderView le dessine. Les nouveaux tests remplacent seulement le panneau et observent les modèles envoyés par refresh, y compris hors groupe et après dissolution. La borne de la pastille demandée en R2-05 est aussi présente. |
| MIN-002 | LOW | Neuf surcharges répètent le même encodeur JSON | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:2231 — Les neuf surcharges sont remplacées par une seule fonction générique Encodable, avec les mêmes réglages JSON. |
| MIN-003 | LOW | Quatre contrôles de plage portent sur des valeurs déjà bornées | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1531 — Les quatre branches de plage sur maxDepth, rows et columns ont été retirées. Les initialisateurs conservent les bornes antérieures. Une autre garde inatteignable préexistante, sur les raccourcis normalisés, est relevée séparément dans MIN-005. |
| MIN-004 | LOW | Deux pipelines presque identiques gèrent les déplacements de bureau | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DesktopCommands.swift:149 — assignActiveWindow et assign(windowID:...) délèguent au même corps moveWindow. Les gardes restent aux entrées, et les règles de placement/pin/intent sont centralisées. |
| PERF-007 | LOW | Le lecteur de ligne réanalyse tout le préfixe à chaque paquet | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift:384 — readLine cherche le saut de ligne dans le seul fragment reçu. Chaque octet est parcouru une fois pour cette recherche : le coût quadratique du préfixe a disparu. La taille de réponse reste Int.max; le défaut algorithmique constaté est corrigé, sans assertion de gain de latence mesuré. |
| QUAL-001 | LOW | Les guides décrivent des interactions qui ne correspondent plus au code | **résolu** | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/README.fr.md:534 — Les README FR/EN décrivent le glisser au bouton droit. Les deux guides attribuent le drag/drop au rail. Les pages CLI documentent explicitement l’exception search_hotkey. Les gestes concordent avec handleRightMouse et la création de WindowDragReorderController dans RailController. |

Les éléments résolus sont confirmés sur leurs scénarios précis. Exemple : PERF-004 est résolu dans la réparation des voisines ; PERF-009 identifie une autre boucle de calcul des minima. REL-031 est résolu pour masterStack ; REL-033 vise le moteur bsp. Ces distinctions évitent de compter deux fois le même défaut.

## Findings par sévérité

| ID | Sévérité | Origine | Constat | Fichier et ligne |
|---|---|---|---|---|
| PERF-008 | HIGH | Nouveau | Le plan BSP dwindle reste quadratique sans priorité de redimensionnement | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:151 |
| PERF-009 | HIGH | Nouveau | La réparation des refus reparcourt tous les résultats pour chaque fenêtre | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:2781 |
| REL-001 | HIGH | Résiduel | Des arguments stage peuvent encore arrêter le daemon | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1704 |
| REL-012 | MEDIUM | Résiduel | La portée frontmost_window saute encore le contrôle de focus | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:807 |
| REL-021 | MEDIUM | Résiduel | Des commandes annoncent un échec après leurs effets ou leur première écriture | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutCommandService.swift:230 |
| REL-032 | MEDIUM | Résiduel | La désinstallation laisse les composants modulaires actifs | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/uninstall:30 |
| REL-033 | MEDIUM | Nouveau | Le mode bsp conserve un espacement qui pousse ses tuiles hors du conteneur | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:97 |
| REL-034 | MEDIUM | Nouveau | Une valeur default_strategy inconnue est déclarée valide puis remplacée par bsp | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:164 |
| REL-035 | MEDIUM | Nouveau | L’enregistrement d’une affinité altère encore certaines chaînes de règles | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleAffinityService.swift:197 |
| REL-036 | MEDIUM | Nouveau | Un lecteur garde le glisser actif après son relâchement explicite | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:87 |
| REL-037 | MEDIUM | Nouveau | Les actions de stage perdent le bureau de la cible | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:473 |
| REL-039 | MEDIUM | Nouveau | La réorganisation du rail ignore les stages vides dans le rang transmis | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:396 |
| REL-040 | MEDIUM | Nouveau | Le mode parallax sélectionne une autre fenêtre que la vignette visible | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCardView.swift:646 |
| MIN-005 | LOW | Nouveau | Le contrôle des raccourcis vides reste inatteignable après leur normalisation | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1566 |
| OBS-002 | LOW | Nouveau | Un caractère UTF-8 coupé rend la fin du journal entièrement vide | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/EventLog.swift:228 |
| OBS-003 | LOW | Nouveau | Le nettoyage annonce applied malgré une suppression refusée | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift:220 |
| REL-038 | LOW | Nouveau | Une macro tronquée peut rejouer un appui sans son relâchement | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:475 |
| REL-041 | LOW | Nouveau | Le lanceur de tests laisse son dossier HOME temporaire | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/test:11 |
| REL-042 | LOW | Nouveau | Les mots contenus dans un identifiant peuvent transformer un succès sans effet en échec | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:272 |

## Détail des findings

### PERF-008 — HIGH — Le plan BSP dwindle reste quadratique sans priorité de redimensionnement

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:151
**Statut :** confirmé par lecture intégrale et analyse des parcours ; non profilé. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** La politique dwindle divise en une fenêtre et toutes les suivantes. splitRatio parcourt chaque sous-liste par contains, puis unionFrame. Lorsque priorityWindowIDs est vide, aucune largeur prioritaire ne peut exister et tous les chemins retournent 0,5, mais les parcours ont déjà été exécutés. Le travail est O(n²) pour un plan ordinaire dwindle. Le compromis commenté dans BSPTree concerne le moteur à arbre persistant, pas cette stratégie, et aucune borne numérique imposée ne limite ici la liste.
**Scénario :** Appeler LayoutPlanner.plan avec mode=.bsp, splitPolicy="dwindle", windowIDs=[1,...,n], currentFrames quelconque et priorityWindowIDs/newWindowIDs vides. Les sous-listes de tailles n, n-1, ..., 2 sont reparcourues ; aucune priorité ne peut changer le ratio 0,5. Ces paramètres proviennent du plan courant lorsque split_policy="dwindle" est configuré.
**Impact :** CPU et allocations évitables à chaque calcul de disposition dans cette politique. HIGH suit la convention algorithmique v14 appliquée lors du premier audit ; aucun gel ni temps absolu n’est revendiqué.

```swift
        let anyPriority = left.contains { priorityWindowIDs.contains($0) }
            || right.contains { priorityWindowIDs.contains($0) }
        if !anyPriority {
            let leftHasNew = left.contains { newWindowIDs.contains($0) }
            let rightHasNew = right.contains { newWindowIDs.contains($0) }
            if leftHasNew || rightHasNew {
                return 0.5
```

**Correction :** Retourner 0,5 dès l’entrée de splitRatio lorsque l’ensemble des fenêtres prioritaires est vide. La correction complète de cette méthode ci-dessous élimine le cas prouvé. Le chemin avec priorités doit être étudié séparément avec des agrégats de sous-arbres avant toute promesse de complexité globale.
**Validation :** Comparer les placements avant/après pour les deux politiques, frames absentes ou présentes, fenêtres nouvelles et priorités. Profiler séparément le chemin sans priorité pour des tailles croissantes, en suivant durée CPU et allocations. Tous les tests LayoutPlannerTests doivent conserver leurs attentes. Correction fournie non compilée ici.
**Effort :** XS. **Risque de régression :** LOW.
**Motif de sévérité :** HIGH selon le module04 v14, comme l’audit initial : parcours quadratique évitable sur un chemin de disposition non borné. Aucune latence réelle mesurée; usage local, pas endpoint réseau distant.
**Contre-audit :** CONFIRMED. Voir /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/counter-audit.json
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:43 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1677 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieTilerTests/LayoutPlannerTests.swift:66 — 

**Exemple de correction proposé, non appliqué :**

```
    private func splitRatio(
        left: ArraySlice<WindowID>,
        right: ArraySlice<WindowID>,
        rect: CGRect,
        horizontal: Bool,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>
    ) -> CGFloat {
        // Sans redimensionnement prioritaire, tous les chemins rendent déjà 0,5.
        guard !priorityWindowIDs.isEmpty else { return 0.5 }
        // Nouvelle fenetre : split 50/50 plutot qu'heriter de la frame macOS arbitraire.
        // Exception : si un resize explicite (priority)
        // est en cours dans ce split, on laisse le calcul priority habituel.
        let anyPriority = left.contains { priorityWindowIDs.contains($0) }
            || right.contains { priorityWindowIDs.contains($0) }
        if !anyPriority {
            let leftHasNew = left.contains { newWindowIDs.contains($0) }
            let rightHasNew = right.contains { newWindowIDs.contains($0) }
            if leftHasNew || rightHasNew {
                return 0.5
            }
        }

        guard let leftFrame = unionFrame(for: left, in: currentFrames),
              let rightFrame = unionFrame(for: right, in: currentFrames)
        else { return 0.5 }

        let usableExtent = horizontal ? rect.width - innerGap : rect.height - innerGap
        guard usableExtent > 0 else { return 0.5 }

        let priorityLeftFrame = unionPriorityFrame(for: left, in: currentFrames, priorityWindowIDs: priorityWindowIDs)
        let priorityRightFrame = unionPriorityFrame(for: right, in: currentFrames, priorityWindowIDs: priorityWindowIDs)

        guard isManagedSplit(leftFrame: leftFrame, rightFrame: rightFrame, rect: rect, horizontal: horizontal) else {
            if let priorityLeftFrame {
                let extent = horizontal ? priorityLeftFrame.width : priorityLeftFrame.height
                return (extent / usableExtent).clamped(to: 0.1...0.9)
            }
            if let priorityRightFrame {
                let extent = horizontal ? priorityRightFrame.width : priorityRightFrame.height
                return ((usableExtent - extent) / usableExtent).clamped(to: 0.1...0.9)
            }
            return 0.5
        }

        let leftEdge = horizontal ? leftFrame.maxX - rect.minX : leftFrame.maxY - rect.minY
        let rightEdge = horizontal ? rightFrame.minX - innerGap - rect.minX : rightFrame.minY - innerGap - rect.minY

        if let priorityLeftFrame {
            let priorityExtent = horizontal ? priorityLeftFrame.width : priorityLeftFrame.height
            let ratio = containsOnlyPriority(left, priorityWindowIDs) ? leftEdge / usableExtent : priorityExtent / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }
        if let priorityRightFrame {
            let priorityExtent = horizontal ? priorityRightFrame.width : priorityRightFrame.height
            let ratio = containsOnlyPriority(right, priorityWindowIDs) ? rightEdge / usableExtent : (usableExtent - priorityExtent) / usableExtent
            return ratio.clamped(to: 0.1...0.9)
        }
        return 0.5
    }
```

### PERF-009 — HIGH — La réparation des refus reparcourt tous les résultats pour chaque fenêtre

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:2781
**Statut :** confirmé par lecture statique ; scénario décrit, non exécuté par ce sous-audit. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** resolveInfeasibleClampedScopes appelle knownMinimumSize pour chaque ID du scope. Ce helper parcourt à chaque fois tous les éléments de result.items, même ceux des autres scopes. Le coût de préparation des minimums est O(n·r), avant le rejet par aire de minimumSizeArrangement. Aucun plafond de n ou r ne précède ce parcours ; le commentaire « n petit » ne donne aucune borne.
**Scénario :** Préparer un stage actif .bsp avec n fenêtres visibles et un writer qui renvoie, pour deux fenêtres, le cadre plein écran au lieu de la taille demandée ; pour les autres, il rend le cadre demandé. Les deux refus se chevauchent, leur union ne laisse pas de conteneur pour réparer les voisines. La passe atteint resolveInfeasibleClampedScopes puis effectue n parcours de r=n résultats. Le test existant mutuallyClampedOversizedWindowsIsolateLargestWindowInsteadOfThrashing couvre cette branche à deux fenêtres ; agrandir son fournisseur démontre la croissance.
**Impact :** Travail CPU quadratique évitable dans une passe synchrone de réparation. La fréquence réelle et la latence n’ont pas été mesurées. Sévérité HIGH selon le minimum v14 de l’anti-pattern recherche linéaire répétée, comme PERF-004 initial ; aucun gel mesuré n’est allégué.

```swift
                .compactMap { requestedFrames[$0] ?? liveFrames[$0] }
                .reduce(CGRect.null) { $0.union($1) }
                .intersection(visibleFrame)
            var minimumSizes = orderedIDs.reduce(into: [WindowID: CGSize]()) { sizes, id in
                sizes[id] = knownMinimumSize(of: id, in: result)
            }
            // Deux essais au plus : le premier peut révéler de nouveaux minimums.
            var arranged = false
            for _ in 0..<2 {
```

**Correction :** Construire les tailles connues par ID en un passage des fenêtres puis des résultats, et supprimer le helper à recherche répétée. Pour plusieurs scopes, l’index des résultats peut aussi être partagé hors de leur boucle.
**Validation :** Comparer les dictionnaires de minimums avant/après avec 10, 100 et 1000 fenêtres synthétiques, plusieurs refus du même ID et des résultats de scopes distincts. Vérifier aussi les cadres et l’ordre des tests de réparation existants. Compter les visites de result.items ; attendu r par scope au lieu de n·r. Mesurer la préparation isolée, puis la passe entière. Revenir au helper précédent si les tailles ou les placements diffèrent.
**Effort :** S. **Risque de régression :** MEDIUM.
**Motif de sévérité :** HIGH selon le module04 v14, comme l’audit initial : parcours quadratique évitable sur un chemin de disposition non borné. Aucune latence réelle mesurée; usage local, pas endpoint réseau distant.
**Contre-audit :** CONFIRMED. Voir /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/counter-audit.json
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:2852 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/LayoutMaintainerTests.swift:1792 — 

**Exemple de correction proposé, non appliqué :**

```
// Dans resolveInfeasibleClampedScopes, remplacer le reduce par :
var minimumSizes = knownMinimumSizes(of: orderedIDs, in: result)

// Remplacer knownMinimumSize par ce helper ; O(n + r) par scope.
private func knownMinimumSizes(of windowIDs: [WindowID], in result: ApplyResult) -> [WindowID: CGSize] {
    let floor = CGSize(width: LayoutTolerance.minimumTileSide, height: LayoutTolerance.minimumTileSide)
    var sizes: [WindowID: CGSize] = [:]
    for id in windowIDs {
        var size = floor
        if let known = clampedFrames[id.rawValue] {
            size = Self.largest(size, Self.minimumSize(requested: known.requested, actual: known.actual))
        }
        sizes[id] = size
    }
    for item in result.items where item.status == .clamped {
        guard let actual = item.actual, let current = sizes[item.windowID] else { continue }
        sizes[item.windowID] = Self.largest(current, Self.minimumSize(requested: item.requested, actual: actual))
    }
    return sizes
}
```

### REL-001 — HIGH — Des arguments stage peuvent encore arrêter le daemon

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1704
**Statut :** confirmé par lecture et contre-audit indépendant; StageID Int.max et débordement démontrés par sonde non fatale; aucun crash daemon exécuté. **Origine :** résiduel d’un constat initial.
**Description :** Les identifiants de stage sont des chaînes non vides sans borne numérique. nextGeneratedStageID convertit ceux qui représentent un Int puis ajoute 1 au plus grand sans contrôler le dépassement. Une stage dont l’identifiant vaut Int.max fait donc échouer assign-empty dès que les stages vides non personnalisées sont épuisées. Un second chemin accepte UInt32(0) pour stage summon puis construit WindowID(0), dont la précondition arrête le processus. Ces commandes sont routées au daemon.
**Scénario :** Dans un état isolé avec un écran, une fenêtre gérée active dans la seule stage 1 et aucune workspace configurée : exécuter roadie stage create 9223372036854775807 Limite puis roadie stage assign-empty. La stage 1 est occupée et la stage Limite porte un nom personnalisé : nextEmptyStageID appelle nextGeneratedStageID; Int.max + 1 déclenche une erreur fatale Swift. Ne pas exécuter contre le daemon de travail. Variante directe avec écran actif : roadie stage summon 0. Le routeur accepte zéro et atteint la précondition WindowID > 0. Aucun crash réel provoqué pendant l’audit.
**Impact :** Arrêt du processus qui traite la commande; le routage daemon rend le gestionnaire indisponible et peut interrompre la gestion des fenêtres.

```swift
    private func nextGeneratedStageID(in scope: PersistentStageScope) -> StageID {
        let numericIDs = scope.stages.compactMap { Int($0.id.rawValue) }
        let next = (numericIDs.max() ?? scope.stages.count) + 1
        return StageID(rawValue: String(next))
    }
```

**Correction :** Contrôler l’addition avec addingReportingOverflow et choisir un identifiant non numérique libre en cas de dépassement. Tester la commande complète avec Int.max en processus isolé.
**Validation :** Fixture avec la stage 1 occupée et une stage personnalisée Int.max : assignEmpty doit renvoyer un résultat normal et un nouvel ID libre, sans arrêt. Garder aussi les cas aucun ID numérique, ID maximum ordinaire et présence d’une stage vide réutilisable. Ajouter stage summon 0 : code64 et aucune fin de processus. Tester aussi les conversions WindowID des commandes group.
**Effort :** XS. **Risque de régression :** LOW.
**Contre-audit :** CONFIRMED. Voir /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/counter-audit.json
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1695 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:989 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Identifiers.swift:29 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:1064 — UInt32(0) accepté; WindowID construit ligne1076.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Identifiers.swift:48 — Précondition rawValue > 0.

**Exemple de correction proposé, non appliqué :**

```
private func nextGeneratedStageID(in scope: PersistentStageScope) -> StageID {
    let used = Set(scope.stages.map { $0.id.rawValue })
    let numericIDs = used.compactMap { Int($0) }
    let (next, overflow) = (numericIDs.max() ?? scope.stages.count).addingReportingOverflow(1)
    if !overflow {
        return StageID(rawValue: String(next))
    }
    var candidate = "stage-\(UUID().uuidString)"
    while used.contains(candidate) {
        candidate = "stage-\(UUID().uuidString)"
    }
    return StageID(rawValue: candidate)
}

// Dans runStageCommand, branche summon, remplacer le guard existant :
guard let rawWindowID = args.dropFirst().first, let id = UInt32(rawWindowID), id > 0 else {
    err("roadie: stage summon requires a positive window id")
    return 64
}
```

### REL-012 — MEDIUM — La portée frontmost_window saute encore le contrôle de focus

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:807
**Statut :** confirmé par lecture complète ; scénario GUI non exécuté. **Origine :** résiduel d’un constat initial.
**Description :** Les cibles de frontmostWindowCandidates sont converties sans scope.windowId. TargetHintService ne demande donc aucun focus et LiveAppTargetProvider.click ne vérifie pas le focus. La relecture du cadre ne détecte pas une fenêtre recouverte : son élément AX peut rester valide aux mêmes coordonnées.
**Scénario :** Configurer target_mode.overlay_enabled=true, target_mode.app_mouse_actions_enabled=true, app_targets.scope="frontmost_window". Avec deux fenêtres flottantes, ouvrir `roadie targets interactive --source app --include-app-targets --action click` sur A. Cliquer à la souris la barre de titre de B pour recouvrir un bouton de A, sans déplacer A ni fermer son overlay. Valider la lettre du bouton de A. La cible ne porte aucun windowId, son cadre AX est inchangé et le clic part sur B.
**Impact :** Une action validée sur A peut toucher une autre fenêtre. La réponse annonce changed=true malgré le focus absent.

```swift
        if let windowID = target.scope.windowId, let pid = AppTargetQueryService.pid(of: target) {
            switch waitForFocus(windowID, pid, 0.5) {
            case .focused:
                break
            case .windowGone:
                return TargetActionResult(changed: false, message: "stale_target: \(target.id)", target: target, error: "stale_target")
            case .timedOut:
                return TargetActionResult(changed: false, message: "focus_failed: \(target.id)", target: target, error: "focus_failed")
```

**Correction :** Renseigner windowId aussi dans frontmostWindowCandidates. Refuser ensuite tout clic applicatif sans identité de fenêtre ; ne pas considérer la vérification du focus comme optionnelle.
**Validation :** Tester une cible sans windowId avec currentFrame inchangé et un émetteur espion : zéro événement, erreur explicite. Tester que le constructeur frontmost_window fournit le windowId ; répéter manuellement le recouvrement A/B sur macOS.
**Effort :** S. **Risque de régression :** MEDIUM.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:426 — Production des cibles sans windowId.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:284 — targets(from:) conserve le scope vide par défaut.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:438 — La demande de focus est également conditionnelle.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:645 — frontmost_window est la portée par défaut.

**Exemple de correction proposé, non appliqué :**

```
// Dans frontmostWindowCandidates, après la résolution de window :
guard let windowID = axWindowElements(pid: app.processIdentifier).first(where: { CFEqual($0.value, window) })?.key else {
    return AppTargetQueryReport(error: "no_focused_window")
}
// Appliquer ce scope à chaque cible convertie avant de la retourner :
let targets = AppTargetQueryService.targets(from: result.pass.candidates, config: config).map { candidate in
    var target = candidate
    target.scope.windowId = windowID
    return target
}
// Dans click, avant le switch sur waitForFocus :
guard let windowID = target.scope.windowId, let pid = AppTargetQueryService.pid(of: target) else {
    return TargetActionResult(changed: false, message: "stale_target: \(target.id)", target: target, error: "stale_target")
}
```

### REL-021 — MEDIUM — Des commandes annoncent un échec après leurs effets ou leur première écriture

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutCommandService.swift:230
**Statut :** confirmé par lecture des chaînes complètes; injection runtime non exécutée par ce sous-agent. **Origine :** résiduel d’un constat initial.
**Description :** zoomParent agrandit la fenêtre avant de persister l’intent. Si cette écriture échoue, la commande retourne changed=false sans retour arrière. Les transferts de bureau, de fenêtre et de stage ont la variante inverse : l’affectation est déjà sur disque lorsque le retrait d’intent échoue; ils retournent le même résultat de refus. R2-01 a corrigé toggleZoom/setMode/balance, mais le défaut reste dans les autres points d’entrée. StateAudit.heal conserve aussi mutate non checked : un échec de stockage peut laisser un nombre de réparations positif sans écriture effective.
**Scénario :** Fixture PowerUserProvider/PowerUserWriter avec fenêtre active non agrandie, stages valides et LayoutIntentStore dont le fichier contient « { pas du json ». Appeler LayoutCommandService.zoomParent : writer.frames reçoit la taille de l’écran avant saveChecked, puis le résultat porte changed=false et failed. Variante : même fichier d’intents corrompu, appeler DesktopCommandService.assignActiveWindow(to:2); l’appartenance persistée passe au bureau 2 et le pin est retiré avant le refus annoncé. Variante heal : état sans activeDisplayID et répertoire non inscriptible, snapshot non persistant avec un écran; mutate calcule une réparation, l’écriture échoue, active-display reste warn/none et le rapport peut encore sortir en succès.
**Impact :** L’utilisateur reçoit un refus alors que son écran ou son affectation a changé. Un réessai peut être ignoré comme déjà effectué, et le maintien peut appliquer l’état partiellement validé.

```swift
        let plan = ApplyPlan(commands: [ApplyCommand(window: entry.window, frame: display.visibleFrame)])
        let result = service.apply(plan, generation: generation)
        do {
            try service.saveLayoutIntentChecked(
                scope: context.scope,
                windowIDs: [activeID],
                placements: [activeID: result.items.first?.actual ?? display.visibleFrame],
                source: .command,
                zoomedWindowID: activeID
```

**Correction :** Persister la décision avant l’effet AX. Regrouper les écritures dépendantes ou restaurer les valeurs précédentes si une étape échoue; si un retour arrière échoue, exposer explicitement un résultat partiel. Étendre aux transferts la stratégie déjà appliquée à setMode et balance.
**Validation :** Injecter séparément un intent illisible et un échec d’écriture tardif. Vérifier le résultat, writer.frames, le bureau/stage du membre, son pin et l’intent précédent. Après refus sans résultat partiel, ces valeurs doivent être inchangées; une passe de maintien ne doit pas déclencher l’opération refusée. Injecter ces pannes dans WindowContextActions et StateAudit.heal; aucune réparation non persistée ne doit être déclarée réussie.
**Effort :** M. **Risque de régression :** MEDIUM.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DesktopCommands.swift:205 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowCommands.swift:776 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:672 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowContextActions.swift:373 — État persistant modifié avant retrait faillible de l’intent.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StateAudit.swift:82 — heal conserve mutate non checked et peut compter des réparations non persistées.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:366 — state heal déduit le code seulement de report.audit.failed.

**Exemple de correction proposé, non appliqué :**

```
// Exemple pour zoomParent : écrire l'intent avant l'effet AX.
let previous = service.effectiveIntentStore.intent(for: context.scope)
do {
    try service.saveLayoutIntentChecked(
        scope: context.scope,
        windowIDs: [activeID],
        placements: [activeID: display.visibleFrame],
        source: .command,
        zoomedWindowID: activeID
    )
} catch {
    return persistenceFailure("layout zoom-parent", error)
}
let plan = ApplyPlan(commands: [ApplyCommand(window: entry.window, frame: display.visibleFrame)])
let result = service.apply(plan, generation: generation)
if result.failed == result.attempted {
    do {
        if let previous { try service.effectiveIntentStore.saveChecked(previous) }
        else { try service.effectiveIntentStore.removeChecked(scope: context.scope) }
    } catch {
        return LayoutCommandResult(message: "layout zoom-parent: failed, rollback failed: \(error)", changed: true)
    }
}
```

### REL-032 — MEDIUM — La désinstallation laisse les composants modulaires actifs

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/uninstall:30
**Statut :** confirmé par lecture; scénario non exécuté. **Origine :** résiduel d’un constat initial.
**Description :** La désinstallation délègue l’arrêt à scripts/stop, qui ne traite que le PID du daemon central. Le lanceur modulaire fournit aussi rail, border, focus-mouse, titlebar-menu et target-mode, chacun dans un processus distinct. Après l’arrêt du tiler, ces composants continuent de fonctionner alors que la désinstallation supprime les binaires et peut supprimer l’état.
**Scénario :** Dans un environnement isolé, lancer scripts/start-modular puis scripts/uninstall. Le PID roadied du tiler est arrêté. Les processus enregistrés dans rail.pid, border.pid, focus-mouse.pid, titlebar-menu.pid et target-mode.pid ne sont jamais inspectés; ils restent actifs après les suppressions.
**Impact :** Des overlays et le focus souris continuent après la désinstallation. La suppression facultative de l’état peut retirer leurs fichiers de verrou alors qu’ils les détiennent encore.

```
# 2. Arrêter le LaunchAgent ET toute instance autonome (Roadie.app, tmux) avec la procédure de
# scripts/stop. Si l'arrêt n'est pas confirmé, rien n'est supprimé : une instance encore vivante
# continuerait à gérer les fenêtres et à recréer ses fichiers d'état.
if ! "$script_dir/stop"; then
  echo "ERREUR : roadied n'est pas arrêté (voir ci-dessus). Désinstallation interrompue, rien n'a été supprimé." >&2
  exit 1
fi

# 3. Supprimer le LaunchAgent et les binaires installés.
rm -f "$plist" "$local_bin_dir/roadied" "$local_bin_dir/roadie"
```

**Correction :** Étendre l’arrêt aux composants réellement lancés, avec vérification de chaque exécutable et attente bornée; refuser toute suppression tant qu’un composant reste vivant. Une protection minimale sûre est de refuser la désinstallation lorsqu’un PID modulaire est encore vivant.
**Validation :** Ajouter un test de cycle de vie simulé avec tiler et cinq composants actifs. Exiger soit leur arrêt vérifié, soit un échec sans aucune suppression. Ajouter le cas composant résistant à l’arrêt.
**Effort :** S. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/stop:22 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/start-modular:47 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/roadied/main.swift:479 — 

**Exemple de correction proposé, non appliqué :**

```
for component in rail border focus-mouse titlebar-menu target-mode; do
  component_pidfile="$HOME/.roadies/$component.pid"
  [[ -f "$component_pidfile" ]] || continue
  component_pid="$(cat "$component_pidfile")"
  if [[ "$component_pid" =~ ^[1-9][0-9]*$ ]] && ps -p "$component_pid" -o comm= >/dev/null 2>&1; then
    echo "Désinstallation refusée : $component est encore actif (PID $component_pid)." >&2
    exit 1
  fi
done
```

### REL-033 — MEDIUM — Le mode bsp conserve un espacement qui pousse ses tuiles hors du conteneur

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:97
**Statut :** confirmé par lecture et sonde isolée utilisant le code compilé de la branche; aucun effet sur le bureau. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** La correction des espacements couvre masterStack et BSPTree. BSPLayoutStrategy reste appelée pour le mode bsp. Elle ramène la dimension utile à zéro mais ajoute encore tout innerGap à la position du second enfant. Aucune borne amont n’empêche une configuration gaps_inner supérieure au conteneur.
**Scénario :** LayoutPlanner.plan avec mode=.bsp, conteneur (0,0,1000,500), deux fenêtres, innerGap=1500, sans marges. usableWidth=0 ; la première tuile a une largeur nulle et la seconde commence à x=1500, hors du conteneur. La variante verticale existe avec un conteneur haut et gap supérieur à sa hauteur.
**Impact :** Une configuration numérique acceptée produit des cadres vides ou hors écran ; le résultat AX peut être refusé ou ajusté. Ce défaut est distinct du cas masterStack corrigé dans REL-031.

```swift
        let leftWidth = floor(usableWidth * ratio)
        let rightWidth = usableWidth - leftWidth
        let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
        let rightRect = CGRect(x: rect.minX + leftWidth + innerGap, y: rect.minY, width: rightWidth, height: rect.height)

        split(windows: leftWindows, rect: leftRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        split(windows: rightWindows, rect: rightRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
```

**Correction :** Borner l’écart à la dimension de chaque split avant de calculer les deux cadres ; réutiliser BSPTree.gap(for:in:innerGap:), déjà présent dans le même module. Transmettre l’écart effectif au calcul du ratio et conserver l’écart demandé pour les splits descendants.
**Validation :** Ajouter des cas .bsp balanced et dwindle avec conteneurs 1000×500 et 500×1000 et gap=1500. Pour les conteneurs non dégénérés, vérifier des cadres non vides et dans le conteneur. Conserver les attentes des gaps 0 et 10.
**Effort :** S. **Risque de régression :** MEDIUM.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:86 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/BSPLayoutStrategy.swift:117 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/LayoutTypes.swift:76 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DaemonSnapshot.swift:1684 — 

**Exemple de correction proposé, non appliqué :**

```
    private func splitHorizontally(
        leftWindows: ArraySlice<WindowID>,
        rightWindows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        let effectiveGap = BSPTree.gap(for: .vertical, in: rect, innerGap: innerGap)
        let usableWidth = max(0, rect.width - effectiveGap)
        let ratio = splitRatio(
            left: leftWindows,
            right: rightWindows,
            rect: rect,
            horizontal: true,
            innerGap: effectiveGap,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            newWindowIDs: newWindowIDs
        )
        let leftWidth = floor(usableWidth * ratio)
        let rightWidth = usableWidth - leftWidth
        let leftRect = CGRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height)
        let rightRect = CGRect(x: rect.minX + leftWidth + effectiveGap, y: rect.minY, width: rightWidth, height: rect.height)

        split(windows: leftWindows, rect: leftRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        split(windows: rightWindows, rect: rightRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
    }

    private func splitVertically(
        topWindows: ArraySlice<WindowID>,
        bottomWindows: ArraySlice<WindowID>,
        rect: CGRect,
        innerGap: CGFloat,
        currentFrames: [WindowID: CGRect],
        priorityWindowIDs: Set<WindowID>,
        newWindowIDs: Set<WindowID>,
        splitPolicy: String,
        placements: inout [WindowID: CGRect]
    ) {
        let effectiveGap = BSPTree.gap(for: .horizontal, in: rect, innerGap: innerGap)
        let usableHeight = max(0, rect.height - effectiveGap)
        let ratio = splitRatio(
            left: topWindows,
            right: bottomWindows,
            rect: rect,
            horizontal: false,
            innerGap: effectiveGap,
            currentFrames: currentFrames,
            priorityWindowIDs: priorityWindowIDs,
            newWindowIDs: newWindowIDs
        )
        let topHeight = floor(usableHeight * ratio)
        let bottomHeight = usableHeight - topHeight
        let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: topHeight)
        let bottomRect = CGRect(x: rect.minX, y: rect.minY + topHeight + effectiveGap, width: rect.width, height: bottomHeight)

        split(windows: topWindows, rect: topRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
        split(windows: bottomWindows, rect: bottomRect, innerGap: innerGap, currentFrames: currentFrames, priorityWindowIDs: priorityWindowIDs, newWindowIDs: newWindowIDs, splitPolicy: splitPolicy, placements: &placements)
    }
```

### REL-034 — MEDIUM — Une valeur default_strategy inconnue est déclarée valide puis remplacée par bsp

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:164
**Statut :** confirmé par lecture du décodage, du validateur et du rechargement ; scénario non exécuté. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Le décodeur transforme toute valeur de stratégie non reconnue en bsp. Le validateur ne vérifie que les noms de clés pour tiling et ne contrôle pas la valeur brute de default_strategy. Le rechargement voit donc un rapport sans erreur et publie cette configuration.
**Scénario :** Fichier contenant [tiling] puis default_strategy = "spatial_bspp". RoadieConfigLoader.validate décode sans erreur et ne produit aucun diagnostic pour cette valeur ; RoadieConfigLoader.load rend .bsp. ConfigReloadService.reload l’accepte.
**Impact :** Une faute dans une valeur de configuration peut sélectionner un autre moteur de disposition sans diagnostic, au lieu de conserver la configuration précédente.

```swift
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawStrategy = try c.decodeIfPresent(String.self, forKey: .defaultStrategy) ?? "bsp"
        self.defaultStrategy = WindowManagementMode(tomlValue: rawStrategy) ?? .bsp
        self.splitPolicy = try c.decodeIfPresent(String.self, forKey: .splitPolicy) ?? "largest_dim"
        self.gapsOuter = try c.decodeFlexibleDouble(forKey: .gapsOuter) ?? 8
        self.gapsOuterTop = try c.decodeFlexibleDouble(forKey: .gapsOuterTop)
```

**Correction :** Réserver bsp au cas où la clé est absente. Lever DecodingError.dataCorruptedError quand une chaîne présente n’est pas un mode ou alias connu.
**Validation :** Tester une clé absente, chacun des modes et alias autorisés, puis "spatial_bspp". La faute doit faire échouer load et validate ; reload doit garder la configuration active.
**Effort :** XS. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1274 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/ConfigReloadService.swift:187 — 

**Exemple de correction proposé, non appliqué :**

```
let rawStrategy = try c.decodeIfPresent(String.self, forKey: .defaultStrategy) ?? "bsp"
guard let strategy = WindowManagementMode(tomlValue: rawStrategy) else {
    throw DecodingError.dataCorruptedError(forKey: .defaultStrategy, in: c, debugDescription: "unknown default_strategy: \(rawStrategy)")
}
self.defaultStrategy = strategy
```

### REL-035 — MEDIUM — L’enregistrement d’une affinité altère encore certaines chaînes de règles

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleAffinityService.swift:197
**Statut :** confirmé par lecture statique ; scénario décrit, non exécuté par ce sous-audit. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** append confond une chaîne vide avec l’absence du champ. toml n’échappe que les barres obliques inverses et les guillemets ; un retour à la ligne décodé reste brut dans une chaîne TOML entre guillemets simples de délimitation. saveRules remplace atomiquement le fichier sans contrôler le résultat décodé. Les actions omises par REL-029 sont rétablies, mais cet aller-retour reste destructif pour certaines valeurs valides.
**Scénario :** Dans le fichier generated, conserver une règle id="empty-title" avec match.app="Terminal", match.title="", action.assign_stage="dev". Enregistrer une affinité pour une autre application : le champ title disparaît et cette règle correspond désormais à tous les titres Terminal. Variante : une chaîne TOML valide contenant l’échappement \n est décodée en LF puis réécrite avec un LF brut ; loadRulesFile échoue ensuite. Ces séquences ne requièrent pas qu’une application macOS fournisse réellement un titre multiligne.
**Impact :** Une opération sans rapport élargit une règle exacte ou rend le fichier de règles illisible. Le résultat de l’ajout annonce changed=true après l’écriture du texte, sans validation de son contenu.

```swift
    private func append(_ key: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.isEmpty else { return }
        lines.append("\(key) = \"\(toml(value))\"")
    }

    private func appendBool(_ key: String, _ value: Bool?, to lines: inout [String]) {
        guard let value else { return }
        lines.append("\(key) = \(value ? "true" : "false")")
```

**Correction :** Conserver toutes les chaînes non nil, y compris vides. Encoder tous les caractères de contrôle TOML ou employer un encodeur existant. Décoder le texte produit et comparer les règles avant le remplacement atomique.
**Validation :** Étendre saveAndRemoveAffinityKeepEveryActionOfOtherRules avec titre vide, LF, CR, tabulation, guillemet et barre inverse. Relire avec RoadieConfigLoader.loadRulesFile après ajout et retrait. Comparer les règles exactes et vérifier qu’une règle au titre vide ne correspond pas à un autre titre.
**Effort :** S. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleAffinityService.swift:207 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleAffinityService.swift:149 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1100 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowRuleMatcher.swift:78 — 

**Exemple de correction proposé, non appliqué :**

```
private func append(_ key: String, _ value: String?, to lines: inout [String]) {
    guard let value else { return }
    lines.append("\(key) = \"\(toml(value))\"")
}

private func toml(_ value: String) -> String {
    var escaped = ""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22: escaped += "\\\""
        case 0x5C: escaped += "\\\\"
        case 0x00...0x1F, 0x7F: escaped += String(format: "\\u%04X", scalar.value)
        default: escaped.unicodeScalars.append(scalar)
        }
    }
    return escaped
}
```

### REL-036 — MEDIUM — Un lecteur garde le glisser actif après son relâchement explicite

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:87
**Statut :** confirmé par lecture et sonde isolée utilisant le code compilé de la branche; aucun effet sur le bureau. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** isActive garde le maximum entre l’échéance déjà lue et celle du fichier. release écrit volontairement une échéance plus courte, mais un consommateur qui a lu le glisser actif ne peut plus adopter cette fin anticipée. suspensionEnd applique le même maximum. Le test existant de release ne lit le consommateur qu’après release et ne couvre pas cet état mémorisé.
**Scénario :** Créer deux WindowDragActivity partageant le même fichier. producteur.markActive(windowID:1, now:t0, holdSeconds:1.5) ; consommateur.isActive(now:t0+0.1) donne true et mémorise t0+1.5. producteur.release(now:t0+0.2) écrit t0+0.2. consommateur.isActive(now:t0+0.3) rend encore true, car max(t0+1.5,t0+0.2)=t0+1.5. Un maintainer avec un scope sans arbre passe includingReleaseGrace=true et conserve cette suspension après le relâchement sans dépôt.
**Impact :** La passe de disposition après un glisser sans dépôt peut rester retardée jusqu’à l’ancienne échéance. Le délai du scénario vient du holdSeconds fourni, pas d’une mesure runtime. Les modes exclusivement à arbre, qui passent includingReleaseGrace=false, ne sont pas concernés par ce retard.

```swift
    public func isActive(now: Date = Date(), includingReleaseGrace: Bool = true) -> Bool {
        guard enabled else { return false }
        lock.lock()
        defer { lock.unlock() }
        let stored = readLocked()
        activeUntil = max(activeUntil, stored?.expiry ?? .distantPast)
        if now <= activeUntil {
            return includingReleaseGrace || (stored?.dragging ?? (activeWindowID != nil))
        }
```

**Correction :** Faire du fichier partagé la source de vérité des lectures, y compris pour une échéance raccourcie. Aligner suspensionEnd. Éviter de supprimer le fichier depuis une lecture expirée, car cela peut aussi effacer une prolongation concurrente.
**Validation :** Étendre releaseWithoutDropEndsDragImmediatelyWithoutGrace : faire lire le consommateur avant release, puis vérifier false immédiatement après et une échéance égale à la release. Ajouter un test du maintainer en bsp avec deux instances. Garder recognizedDropKeepsGraceAndLeavesProofAcrossProcesses vert afin de préserver la grâce des dépôts reconnus.
**Effort :** S. **Risque de régression :** MEDIUM.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:40 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/WindowDragActivity.swift:66 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:224 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/CommandSinglePlanTests.swift:348 — 

**Exemple de correction proposé, non appliqué :**

```
// Le fichier partagé fait foi, y compris quand release raccourcit son échéance.
public func isActive(now: Date = Date(), includingReleaseGrace: Bool = true) -> Bool {
    guard enabled else { return false }
    lock.lock()
    defer { lock.unlock() }
    guard let stored = readLocked(), now <= stored.expiry else { return false }
    return includingReleaseGrace || stored.dragging
}

public func suspensionEnd() -> Date? {
    guard enabled else { return nil }
    lock.lock()
    defer { lock.unlock() }
    guard let expiry = readLocked()?.expiry else { return nil }
    return Date(timeIntervalSinceReferenceDate: expiry.timeIntervalSinceReferenceDate.nextUp)
}
```

### REL-037 — MEDIUM — Les actions de stage perdent le bureau de la cible

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:473
**Statut :** confirmé par lecture de la construction de cible et des appels jusqu’à activeScope ; scénario non exécuté. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Les cibles de stage portent un écran, un bureau et une stage. La liste --include-hidden inclut les stages des autres bureaux et leur propose switch et send-active. Les deux actions ne transmettent que displayId et stageId ; StageCommandService choisit ensuite le bureau actuellement actif.
**Scénario :** Sur un écran E, créer les bureaux 1 et 2 avec chacun une stage 2 ; rester sur le bureau 1, stage 1. Exécuter `roadie targets pick "stage:E/2/2" --include-hidden --action switch`. La stage 2 du bureau 1 est sélectionnée. Avec --action send-active, la fenêtre va dans la stage 2 du bureau 1 au lieu de celle du bureau 2.
**Impact :** Le client sélectionne un identifiant composite exact mais modifie un autre espace de travail. Les scopes homonymes rendent le résultat trompeur.

```swift
    private func activateSwitch(_ target: RoadieTarget) -> TargetActionResult {
        guard target.kind == .stage,
              let displayID = target.scope.displayId,
              let stageID = target.scope.stageId
        else {
            return TargetActionResult(changed: false, message: "unsupported_action: switch for \(target.kind.rawValue)", target: target, error: "unsupported_action")
        }
        let result = StageCommandService(service: service, store: stageStore, events: eventLog).switchTo(stageID, displayID: DisplayID(rawValue: displayID))
        return TargetActionResult(changed: result.changed, message: result.message, target: target, error: result.changed ? nil : "switch_failed")
```

**Correction :** Propager le StageScope complet aux actions. Comme correction minimale, refuser explicitement les cibles d’un autre bureau et ne plus leur proposer ces actions tant que la bascule inter-bureaux n’est pas prise en charge.
**Validation :** Fixture avec bureaux 1 et 2 et stages homonymes. Choisir stage:E/2/2 pendant que 1 est actif. Vérifier soit une action sur le scope exact, soit un refus explicite ; le bureau 1 et ses membres ne doivent pas être modifiés.
**Effort :** S. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:495 — send-active perd lui aussi desktopId.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:600 — Stages des autres bureaux accessibles avec includeHidden.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1058 — switchDisplay choisit activeScope.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1646 — activeScope lit currentDesktopID.

**Exemple de correction proposé, non appliqué :**

```
// Garde à placer dans activateSwitch et activateSendActive, après les identifiants :
let display = DisplayID(rawValue: displayID)
guard let desktopID = target.scope.desktopId,
      stageStore.state().currentDesktopID(for: display).rawValue == desktopID else {
    return TargetActionResult(
        changed: false, message: "target_desktop_not_active: \(target.id)",
        target: target, error: "target_desktop_not_active"
    )
}
```

### REL-039 — MEDIUM — La réorganisation du rail ignore les stages vides dans le rang transmis

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:396
**Statut :** confirmé par lecture complète des producteurs/consommateurs du rang ; UI non exécutée. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Le panneau calcule un rang parmi les seules cartes visibles. StageCommandService transmet ce rang sans conversion à PersistentStageScope.reorderStage, qui l’applique à toutes les stages, y compris les stages vides absentes du rail. Un glisser peut donc ne rien changer ou produire un autre ordre.
**Scénario :** Préparer l’ordre persistant [stage 1 vide, stage 2 avec une fenêtre, stage 3 avec une fenêtre]. Le rail affiche [stage 2, stage 3]. Glisser stage 2 au bouton droit sous stage 3. Le panneau renvoie position=2 ; le store retire stage 2 puis la réinsère à l’indice 1 de [stage 1, stage 3]. Le résultat reste [stage 1, stage 2, stage 3].
**Impact :** Le geste documenté de réorganisation échoue silencieusement dès que des stages invisibles précèdent la destination.

```swift
        var insertionPosition = 1
        for card in targetCards {
            let cardFrame = contentView.convert(card.frame, from: stack)
            if contentPoint.y >= cardFrame.midY {
                return insertionPosition
            }
            insertionPosition += 1
        }
        return insertionPosition
```

**Correction :** Conserver l’ordre complet des stages dans RailPanel et convertir la position visuelle en rang dans cet ordre, après retrait de la source. Une autre solution consiste à transmettre un identifiant de stage voisine et un côté.
**Validation :** Ajouter un test du chemin panneau → reorder avec stages vides avant, entre et après les cartes. [1 vide,2 occupée,3 occupée] + glisser 2 après 3 doit donner l’ordre visible [3,2]. Tester aussi le déplacement vers le haut et une seule carte. Aucun test AppKit ou geste réel exécuté dans cet audit.
**Effort :** S. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:287 — visibleStageIDs = content.stages.map(\.id)
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailController.swift:1264 — RailDisplayContent retire les stages sans membre représenté.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageStore.swift:1149 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:396 — Le rang reçu est transmis tel quel à scope.reorderStage.

**Exemple de correction proposé, non appliqué :**

```
// RailPanel : propriété, puis dans render : allStageIDs = content.scope.stages.map(\.id)
private var allStageIDs: [StageID] = []

// Remplace le calcul final dans stageReorderPosition, après la construction de targetCards.
let remainingIDs = allStageIDs.filter { $0 != sourceStageID }
for card in targetCards {
    let cardFrame = contentView.convert(card.frame, from: stack)
    if contentPoint.y >= cardFrame.midY, let index = remainingIDs.firstIndex(of: card.stageID) {
        return index + 1
    }
}
guard let last = targetCards.last, let index = remainingIDs.firstIndex(of: last.stageID) else { return nil }
return index + 2
```

### REL-040 — MEDIUM — Le mode parallax sélectionne une autre fenêtre que la vignette visible

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCardView.swift:646
**Statut :** confirmé par lecture et calcul géométrique indépendant ; UI non exécutée. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Le dessin applique une compression horizontale et un cisaillement à chaque vignette. Le test du clic utilise encore le rectangle avant transformation, sans appliquer l’inverse au point. Dans une zone de recouvrement, la première vignette intercepte donc le glisser ou le menu d’une autre vignette.
**Scénario :** Afficher deux membres dans une carte de 224×170 points, renderer=parallax-45 avec les paramètres par défaut (rotation 35°, offset_x 25, offset_y 18, scale_per_layer 0.08). Débuter un glisser au point local (35,90). Le premier rectangle brut est (30.6,42,160,86), donc hitPreview le retient. Sa zone dessinée commence pourtant à x=45.06784. Le second aperçu dessiné couvre x=25.31041…145.88959 et contient ce point ; c’est cette seconde fenêtre que voit l’utilisateur.
**Impact :** Le glisser et les actions du menu contextuel peuvent viser la mauvaise fenêtre dans le mode parallax.

```swift
            guard item.rect.contains(point),
                  let member = visualMembers[safe: item.index]
            else { continue }
            return (member, item.rect)
        }
        return nil
```

**Correction :** Définir une transformation affine commune au dessin et au test du clic. Tester chaque rectangle avec le point transformé par son inverse. Réutiliser ce point local pour calculer grabUnit.
**Validation :** Test sur la carte de 224×170 : (35,90) doit sélectionner le second membre. À ce point, l’inverse donne (18.30944,96.35228) hors du premier rectangle, puis (23.82881,94.25166) dans le second. Couvrir rotations 0,35,75°, recouvrements et les autres modes. Les nombres ont été recalculés avec Python à partir des formules lues ; aucune exécution du rendu AppKit ni interaction réelle.
**Effort :** S. **Risque de régression :** MEDIUM.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCardView.swift:581 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCardView.swift:660 — Le chemin parallax retourne les rectangles bruts de previewItems.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailPanel.swift:464 — Le menu utilise card.windowID(at: local), fondé sur hitPreview.

**Exemple de correction proposé, non appliqué :**

```
private func parallaxTransform(for rect: CGRect) -> CGAffineTransform {
    let angle = min(config.parallaxRotation, 75) * .pi / 180
    let scale = max(0.45, cos(angle))
    let shear = sin(angle) * 0.12
    return CGAffineTransform(a: scale, b: shear, c: 0, d: 1,
                             tx: rect.midX * (1 - scale), ty: -rect.midX * shear)
}

// Dans le dessin : context.concatenate(parallaxTransform(for: rect)).
// Dans hitPreview, pour chaque item, avant le guard :
let localPoint = config.mode == .parallax
    ? point.applying(parallaxTransform(for: item.rect).inverted()) : point
guard item.rect.contains(localPoint), let member = visualMembers[safe: item.index] else { continue }
// Transmettre également localPoint à dragPayload pour grabUnit.
```

### MIN-005 — LOW — Le contrôle des raccourcis vides reste inatteignable après leur normalisation

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1566
**Statut :** confirmé par lecture du seul appel privé, du décodage et de normalizedKey. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Le seul appel de validateTargetGrid reçoit la configuration décodée. Son initialiseur remplace déjà les quatre touches vides ou composées d’espaces par space/r/backspace/escape. La branche qui recherche encore une touche vide ne peut donc produire son erreur. Aucune contrainte documentée ne nécessite ce doublon.
**Scénario :** Décoder [experimental.target_grid] confirm_action_key="" ou une valeur uniquement composée d’espaces. normalizedKey applique une touche de repli non vide avant validateTargetGrid ; la branche ne s’exécute pas.
**Impact :** Sept lignes de validation sans effet entretiennent une règle qui semble rejeter les touches vides alors qu’elles sont normalisées en amont.

```swift
        if config.confirmActionKey.isEmpty || config.resetKey.isEmpty || config.backKey.isEmpty || config.exitKey.isEmpty {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.target_grid.*_key",
                message: "recursive grid keys must not be empty"
            ))
        }
```

**Correction :** Supprimer la branche sur les quatre touches vides. Garder les valeurs de repli existantes ; si un rejet est voulu plus tard, valider avant normalisation dans une modification fonctionnelle distincte.
**Validation :** Comparer les rapports de validate pour des touches vides, blanches, absentes et valides ; le résultat doit rester identique.
**Effort :** XS. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:783 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:859 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1284 — 

**Exemple de correction proposé, non appliqué :**

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
    return items
}
```

### OBS-002 — LOW — Un caractère UTF-8 coupé rend la fin du journal entièrement vide

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/EventLog.swift:228
**Statut :** confirmé par lecture et sonde isolée utilisant le code compilé de la branche; aucun effet sur le bureau. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** tail lit des blocs de 64 Kio depuis la fin puis décode tous les octets collectés avant de sélectionner les dernières lignes. La frontière du bloc peut couper un caractère UTF-8 de la première ligne partielle. Le décodage échoue alors et retourne une liste vide, même lorsque les dernières lignes demandées sont complètes et valides.
**Scénario :** Créer un journal UTF-8 de plus de 64 Kio dont les deux dernières lignes se trouvent dans le dernier bloc et dont l’octet situé à taille-65536 est le second octet de « é ». Appeler EventLog(path: chemin).tail(limit: 1). Les deux newlines arrêtent la lecture après un bloc; String(data:encoding:) échoue sur le préfixe UTF-8 incomplet et retourne [].
**Impact :** events tail et les synthèses de performance qui utilisent envelopes peuvent annoncer un journal vide ou zéro échantillon par intermittence.

```swift
            let lineCount = data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
            if lineCount > limit { break }
        }

        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        return Array(raw.split(separator: "\n").suffix(limit).map(String.init))
```

**Correction :** Sélectionner les dernières lignes sur les octets avant le décodage UTF-8. Ainsi le préfixe partiel qui ne fait pas partie du résultat n’invalide pas les lignes finales.
**Validation :** Ajouter un journal de plus de 64 Kio avec la coupe au milieu de é puis d’un emoji, suivi de plusieurs lignes JSON complètes. Exiger les dernières lignes demandées et les événements décodés, sans résultat vide.
**Effort :** S. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/EventLog.swift:213 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/PerformanceLogService.swift:54 — 

**Exemple de correction proposé, non appliqué :**

```
return data.split(separator: 0x0A)
    .suffix(limit)
    .compactMap { String(data: Data($0), encoding: .utf8) }
```

### OBS-003 — LOW — Le nettoyage annonce applied malgré une suppression refusée

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift:220
**Statut :** confirmé par lecture; scénario non exécuté. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Plusieurs branches ignorent l’erreur de removeItem puis placent applied à true sans vérifier le résultat. Le rapport texte et le JSON annoncent alors une suppression réussie alors que le fichier existe encore. Le correctif de rotation stdout/stderr ne couvre pas ces branches de suppression.
**Scénario :** Dans un dossier de configuration temporaire non inscriptible, conserver plus de trois sauvegardes roadies.toml.bak-* puis appeler FileAdministrationService(configPath: chemin).run(dryRun: false) sans privilèges administrateur. removeItem échoue mais chaque action concernée porte applied=true.
**Impact :** Le diagnostic de nettoyage fournit une fausse réussite et masque les fichiers qui occupent encore le disque.

```swift
            var action = FileAdminAction(
                kind: .delete,
                path: url.path,
                reason: reason,
                sizeBytes: recursiveSize(url)
            )
            if !dryRun {
                try? manager.removeItem(at: url)
                action.applied = true
            }
```

**Correction :** Positionner applied uniquement après réussite de la suppression et conserver une erreur explicite dans le rapport ou stderr. Appliquer le même traitement aux sauvegardes d’événements et aux .DS_Store.
**Validation :** Tester une suppression refusée par les permissions ou un FileManager simulé en échec. Exiger applied=false, un diagnostic et le fichier encore présent; conserver le test de suppression réussie.
**Effort :** S. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift:120 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/FileAdministration.swift:203 — 
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/Formatters.swift:369 — 

**Exemple de correction proposé, non appliqué :**

```
if !dryRun {
    do {
        try manager.removeItem(at: url)
        action.applied = true
    } catch {
        action.applied = false
        fputs("roadie: cleanup failed for \(url.path): \(error)\n", stderr)
    }
}
```

### REL-038 — LOW — Une macro tronquée peut rejouer un appui sans son relâchement

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:475
**Statut :** séquence déséquilibrée confirmée par lecture ; effet natif sur le bureau non reproduit. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Le capteur coupe strictement au nombre maximal d’événements et sauvegarde aussi la séquence dès que la durée expire. Il ne complète ni ne retire les gestes encore ouverts. Le replay parcourt cette séquence sans relâcher les boutons ou touches restés appuyés en fin de lecture.
**Scénario :** Configurer target_record.enabled=true, replay_enabled=true, max_events=1 et include_ax_context=false. Enregistrer un clic gauche ; le down est conservé et le up est rejeté par maxEvents. Rejouer le fichier : replay émet seulement leftMouseDown. Même cas si la durée expire pendant un appui.
**Impact :** La macro laisse une séquence de saisie synthétique non équilibrée, susceptible de maintenir une sélection ou un glisser jusqu’à un relâchement ultérieur. Chemin expérimental et ponctuel, sévérité abaissée à LOW.

```swift
    func append(_ event: TargetMacroEvent) {
        guard events.count < maxEvents else { return }
        events.append(event)
    }
```

**Correction :** Suivre les appuis bruts réellement émis et garantir leur relâchement à la fin du replay avec defer. Équilibrer également les enregistrements tronqués, ou signaler leur incomplétude.
**Validation :** Émetteur espion : rejouer [mouseDown] puis [keyDown] et vérifier le relâchement final correspondant. Rejouer une paire complète et vérifier qu’aucun relâchement supplémentaire n’est émis. Tester une capture atteignant max_events juste après un down.
**Effort :** S. **Risque de régression :** MEDIUM.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:274 — Sauvegarde de capture.events sans équilibrage.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:336 — Dernier événement émis, puis fin du replay sans nettoyage.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:937 — max_events accepte la valeur 1.

**Exemple de correction proposé, non appliqué :**

```
// Dans replay(events:), suivre les appuis bruts (le chemin sémantique ne les ajoute pas) :
var heldMouse: [TargetMacroMouseButton: TargetMacroEvent] = [:]
var heldKeys: [Int: TargetMacroEvent] = [:]
defer {
    for var held in heldMouse.values { held.kind = .mouseUp; replay(held) }
    for var held in heldKeys.values { held.kind = .keyUp; replay(held) }
}
// Immédiatement après replay(event) :
switch event.kind {
case .mouseDown: heldMouse[event.mouseButton] = event
case .mouseUp: heldMouse[event.mouseButton] = nil
case .keyDown: if let code = event.keyCode { heldKeys[code] = event }
case .keyUp: if let code = event.keyCode { heldKeys[code] = nil }
default: break
}
```

### REL-041 — LOW — Le lanceur de tests laisse son dossier HOME temporaire

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/test:11
**Statut :** confirmé par lecture; scénario non exécuté. **Origine :** nouveau constat de cet audit; antériorité Git non attribuée sauf précision.
**Description :** Le script enregistre un trap EXIT pour supprimer tmp_home puis utilise exec pour remplacer son shell. Quand exec réussit, ce shell ne passe pas par EXIT. Le wrapper exécute lui aussi exec, sans reprendre le nettoyage; le dossier temporaire est donc conservé après chaque lancement.
**Scénario :** Lancer scripts/test dans un environnement isolé avec un faux scripts/with-xcode qui termine normalement. Le dossier roadie-test-home.* créé au début reste présent après le code de sortie 0. Le même chemin de contrôle s’applique au lancement réel de swift test.
**Impact :** Les exécutions de tests accumulent des dossiers HOME temporaires et les éventuels fichiers qu’elles y créent.

```
tmp_home="$(mktemp -d "${TMPDIR:-/tmp}/roadie-test-home.XXXXXX")"
cleanup() {
  rm -rf "$tmp_home"
}
trap cleanup EXIT

HOME="$tmp_home" exec "$script_dir/with-xcode" swift test "$@"
```

**Correction :** Garder le shell parent pour qu’il exécute son trap à la fin; retirer exec de la dernière ligne. Le code de sortie de la commande reste propagé par set -e.
**Validation :** Tester le wrapper avec une commande simulée qui termine en 0 puis en 1; vérifier le code de sortie et l’absence du répertoire temporaire dans les deux cas.
**Effort :** S. **Risque de régression :** LOW.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/scripts/with-xcode:47 — 

**Exemple de correction proposé, non appliqué :**

```
trap cleanup EXIT
HOME="$tmp_home" "$script_dir/with-xcode" swift test "$@"
```

### REL-042 — LOW — Les mots contenus dans un identifiant peuvent transformer un succès sans effet en échec

**Fichier :** /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:272
**Statut :** confirmé par lecture et sonde isolée utilisant le code compilé de la branche; aucun effet sur le bureau. **Origine :** résiduel connu FR-039/R2-06, préexistant à la session, nouvel ID dans cet audit complet; non supprimé par baseline.
**Description :** actionExitCode recherche ses marqueurs dans tout le message, y compris les valeurs utilisateur. Après création d’une stage failed, sa création répétée renvoie already exists et changed=false mais le code de sortie vaut 1. Le retrait du seul marqueur not visible ne règle pas la cause.
**Scénario :** Sur un écran actif : roadie stage create failed puis même commande. Le second résultat already exists devient code 1, tandis que la même opération sur demo retourne 0. La sonde appelle la fonction réelle sur ces messages, sans toucher au bureau.
**Impact :** Un script reçoit un faux échec pour une action idempotente, selon le nom choisi. Aucun changement destructeur supplémentaire n’est démontré.

```swift
    nonisolated static func actionExitCode(changed: Bool, message: String) -> Int32 {
        guard !changed else { return 0 }
        let failureMarkers = ["not found", "unknown", "requires", "failed", "unavailable", "must "]
        let lowered = message.lowercased()
        return failureMarkers.contains { lowered.contains($0) } ? 1 : 0
    }

```

**Correction :** Ajouter un statut explicite succès/sans-effet/échec dans les résultats métier et calculer le code sur ce statut. Ne plus déduire le statut du texte affiché.
**Validation :** Tester create répété avec identifiants failed, not found, unknown, requires, unavailable, must x et demo : code 0 pour tous les already exists; conserver code1 sur échec réel de persistance.
**Effort :** M. **Risque de régression :** MEDIUM.
**Autres preuves :**
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:348 — Message already exists interpole stageID.

**Exemple de correction proposé, non appliqué :**

```
enum CommandOutcome { case changed, noOp, failed }
func actionExitCode(outcome: CommandOutcome) -> Int32 {
    outcome == .failed ? 1 : 0
}
// Ajouter outcome aux résultats et le renseigner à chaque point de retour.
```

## Minimalisme & Frugalité

Potentiel minimalisme : ~9 lignes suppressibles à comportement constant

Checklist exécutée : code mort, helpers sans utilité, wrappers, état dérivé, abstraction anticipée, fonctions hors besoin, dépendances évitables et chemins de validation inatteignables. Les anciennes surcharges JSON et duplications de pipelines ont été retirées. Le reliquat comprend sept lignes de validation inatteignable (MIN-005) et deux lignes privées jamais lues dans FileAdministration. Aucun grand refactoring n’est proposé sans besoin.

## Vertus LLM & Responsabilité Future

La session réduit la charge cognitive sur les correctifs vérifiés : encodage commun, résultat de persistance contrôlé, fonctions de calcul partagées et tests de comportement plus précis. Le volume ajouté aux verrous, à la validation AX et aux écritures contrôlées répond à des cas documentés. Les abstractions ont un usage réel ; les défauts restants concernent leur application incomplète aux points d’entrée, plutôt qu’un besoin de nouvelles couches.
Les invariants et les tests rendent le code explicable. Les noms de tests ne suffisent toutefois pas : les variantes de fenêtre, de moteur et de panne manquaient encore. Aucune origine LLM du code n’est déduite du style. Aucun service LLM intégré à l’application détecté.

## Complexité algorithmique et performance

Checklist explicite : doubles boucles, recherche linéaire en boucle, N+1 de lecture/API, tris répétés, concaténations répétées, I/O sans regroupement, récursion et copies successives. Les quatre HIGH algorithmiques initiaux sont résolus sur leurs sites. Deux autres cas non bornés sont confirmés : PERF-008 et PERF-009. Les coûts sont déduits du code ; aucune amélioration de latence chiffrée n’est annoncée. Les corrections proposées ont un plan de validation et de retour arrière dans les artefacts.

## Points positifs

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/JSONPersistence.swift:86 : mutation contrôlée distincte, refus de fichier corrompu avant exécution du corps et conservation des octets.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DesktopCommands.swift:176 : pipeline de transfert partagé et validation du bureau courant aux entrées.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/StageCommands.swift:1553 : ensembles construits une fois pour conserver un ordre linéaire.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/WindowGroupCommandTests.swift:26 : vérification des membres et du membre actif après chaque étape métier.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RestoreSafetyService.swift:147 : restauration distingue les Spaces plein écran natifs et les fenêtres absentes sans preuve de fermeture.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift:28 — La collecte linéaire des feuilles et les ensembles suppriment le coût quadratique du placement normal du moteur à arbre.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/Audit022R2LotATests.swift:100 — La réconciliation optimisée est comparée à une référence sur 400 cas déterministes, y compris suppressions et insertions.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieCore/Config.swift:1611 — Le décodage numérique distingue une clé absente d’une valeur de type invalide et propage l’erreur.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieTiler/LayoutStrategy.swift:1 — Le protocole de disposition a quatre implémentations réellement sélectionnées par LayoutPlanner ; cette abstraction répond à des usages présents.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CLICommandRouter.swift:517 — Le rechargement CLI agit sur le service partagé et renvoie un code non nul en cas de validation refusée.
- Module 04 : l’intersection des voisines utilise Set et la détection des trous supprime le parcours cubique ; tests d’équivalence déterministes lus dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/Audit022LotATests.swift.
- Module 06 : heal préserve les membres absents sans preuve de PID mort ; rôles AX et destinations différées ont des tests de maintainer, pas seulement de matcher.
- Module 08 : les mémoires de refus et d’échecs sont purgées par présence et ancienneté dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/LayoutMaintainer.swift:1562 ; TickScheduler conserve une demande bloquée et borne le réarmement des échéances à 15 ms.
- Module 12 : un seul encodeur générique remplace neuf corps. Les helpers de grille portent un invariant géométrique réel ; le fournisseur de rejeu évite un second relevé AX. Le marqueur scratchpad a une justification contractuelle explicite dans la SPEC-002.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift:112 — Le socket Unix naît en 0600 pendant bind; aucune fenêtre de permission plus large.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/roadied/main.swift:624 — Le watcher est lancé avec un tableau d’arguments fixes et un PID noyau, sans construction de shell; les descripteurs hors stdout/stderr ne sont pas hérités.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Package.resolved:10 — La seule dépendance Swift tierce déclarée, TOMLKit, est verrouillée à une révision exacte dans Package.resolved.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/ComponentLockFile.swift:20 — Le protocole d’exclusion CLI/daemon documente l’ordre des verrous et borne l’attente de démarrage; les scénarios sans PID et de démarrage concurrent sont testés.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/EventSubscriptionService.swift:110 — Les ruptures dues à la rétention du journal sont explicites et échappent aux filtres des abonnés.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/CommandSocketServer.swift:393 — Le lecteur de protocole ne rescane plus les octets reçus; la recherche du newline est linéaire.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/roadied/main.swift:171 — Les fonctions de démarrage des composants sont partagées entre modes monolithique et modulaire; elles portent une responsabilité de cycle de vie concrète.
- 03 : les clics applicatifs sont désactivés indépendamment de la lecture des cibles et contrôlés avant action (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetHintService.swift:417). Le nom de macro est restreint aux lettres, chiffres, tirets et underscores (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetMacroService.swift:422).
- 04 : fusion des lots triés de recherche en O(n + b log b), avec plafond explicite de 500 cibles (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TargetSearchModel.swift:39).
- 06 : les résultats AX ne confondent plus erreur de levée de fenêtre et succès ; tests ciblés des erreurs (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieAX/SystemSnapshotProvider.swift:1082).
- 06 : tests du contrôleur et du replay avec événements CGEvent observables sans clic réel (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Tests/RoadieDaemonTests/TargetModeRuntimeControllerTests.swift:147).
- 08 : registre des éléments AX remplacé à chaque parcours et protégé par un verrou ; ajouts des générations dépassées ignorés (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:344). Réévaluation géométrique limitée à deux appels et un budget commun (/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/AppTargetQueryService.swift:865).
- PERF-003 : géométrie du dépôt commune et linéaire, avec test de comparaison contre la version récursive à plusieurs tailles : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/DropPreviewController.swift:488.
- Le menu désactivé évite tout snapshot ; les trois familles partagent exécution et journal : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/TitlebarContextMenuController.swift:209 et :490.
- Le panneau de bordure consomme un modèle testable réellement produit par refresh ; la pastille est bornée : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/BorderController.swift:85 et :259.
- Le rail capture ses vignettes en asynchrone, limite les lots, conserve une icône de repli et purge les fenêtres disparues : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/Sources/RoadieDaemon/RailThumbnailStore.swift:50 et :65.

## Dépendances et zones sensibles

TOMLKit est verrouillée à 0.6.0 et à une révision précise. Aucune conclusion d’absence de CVE sans scan. Le contrôle sécurité a couvert deux recherches distinctes sur permissions, secrets, processus, fichiers et journaux. Aucun nouveau défaut de sécurité confirmé. Absence d’authentification web, de paiement et de moteur LLM ; persistance JSON locale, pas de migration de base SQL. Les permissions effectives du dossier utilisateur et l’historique complet des secrets ne sont pas certifiés.

## Findings supprimés par la baseline

Aucun. Le résiduel FR-039 reste scoré en LOW, même s’il était connu et volontairement laissé pour plus tard.

## Roadmap de remédiation

1. Corriger REL-001 et protéger toutes les conversions d’identifiants ; traiter PERF-008 et PERF-009 avec tests de complexité.
2. Terminer REL-012, REL-021 et REL-032. Corriger les nouveaux MEDIUM avec tests ciblés.
3. Traiter les LOW, dont le statut métier explicite de FR-039 et le nettoyage des dossiers de tests.

## Ce qui n’a pas été vérifié

- 42 tests exclus (CLICommandRouterTests, Audit022LotITests, Audit022R2LotCTests), car leurs sockets imposent des chemins /tmp hors scratch. 1044 tests exécutés avec succès.
- Aucune interaction réelle AX/AppKit, aucun glisser réel, aucun écran branché/débranché, aucun clic ou macro sur le bureau.
- Aucun processus existant arrêté ou relancé. Désinstallation et cycle de vie modulaire vérifiés par lecture seulement.
- Aucun profil CPU/mémoire ni benchmark de latence réelle; HIGH de complexité = règle structurelle du protocole, pas preuve de ralentissement ressenti.
- Aucun taux global JSCPD, mutation testing, couverture instrumentée ou scanner CVE. Dépendance TOMLKit non expertisée en profondeur; historique Git complet non scanné pour secrets.
- Packaging, signature et Gatekeeper non exécutés; permissions et ACL réelles du HOME non auditées.
- Documentation et tests lus selon les risques; seuls les 96 fichiers Swift de production ont tous une lecture intégrale.
- Pointeur audits/latest non modifié, conformément à la restriction utilisateur des écritures.
- Avertissement de compilation existant : modificateur internal dans extension private de DaemonSnapshot.swift:2193; compilation réussie.

## Intégrité et artefacts

Aucun code source corrigé. Aucun commit, stash, checkout ou reset. Seul le dossier de cet audit contient des écritures persistantes.
Empreintes avant/après : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/integrity-check.json
Comparaison machine des 50 constats : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/comparison.json
Constats agrégés : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/cycle-1/aggregated-findings.json
Validation du protocole : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation/audits/2026-10-13/full-codebase-02/validation/session-validator.log
