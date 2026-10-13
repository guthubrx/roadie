# Audit de code v14 — Roadie — dépôt complet

Date : 2026-10-13. Commit vérifié : acc10e13c41026ce444fe38933840b1ea9e2c976. Branche : main. Mode : readonly. Un cycle.

Dépôt : /Users/moi/Nextcloud/10.Scripts/39.roadie

Rapport : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/scoring.md

## Résumé exécutif

**Note globale v14 : B+ (83.16/100).** Cette note est la moyenne pondérée imposée par le protocole. Le domaine fiabilité vaut **F (0/100)**. **La livraison reste bloquée selon la règle v14**, car des constats HIGH subsistent. Une bonne moyenne ne neutralise pas ces défauts.

50 constats : 0 CRITICAL, 7 HIGH, 38 MEDIUM, 5 LOW. Aucun correctif appliqué.

Périmètre : 96 fichiers Swift de production, 38 217 lignes, toutes les cibles et les scripts. Les 96 sources ont été lues entièrement, réparties entre les relectures. Les 71 fichiers de tests ont été inventoriés; 33 ont été lus entièrement, les autres par scénarios et recherches. La documentation courante a été comparée au code. Les anciennes specs ont servi de contexte ciblé. Le taux de 100 % porte sur les sources de production, pas sur les branches testées ni sur une lecture intégrale de chaque document historique.

Build réussi. 880 tests Swift distincts exécutés sur 881. Le lancement initial donne 879 succès et un échec de copie de fixture; le test concerné passe après copie de l’exemple original. Aucun échec produit ne reste observé. Un test socket est exclu, car son chemin /tmp est codé en dur. Sept tests Python du script de mesure passent. Cinq sondes pures confirment des défauts sans modifier les fenêtres réelles.

| Domaine | Note | Score | HIGH | MEDIUM | LOW |
|---|---:|---:|---:|---:|---:|
| security | A | 100 | 0 | 0 | 0 |
| supply_chain | A | 100 | 0 | 0 | 0 |
| observability | A | 97 | 0 | 1 | 0 |
| reliability | F | 0 | 3 | 29 | 0 |
| tests | A- | 88 | 0 | 4 | 0 |
| performance | A | 97 | 0 | 1 | 0 |
| complexity | D | 56 | 4 | 1 | 1 |
| quality | A | 99 | 0 | 0 | 1 |
| architecture | A | 100 | 0 | 0 | 0 |
| ai_hygiene | A | 100 | 0 | 0 | 0 |
| duplication | A | 97 | 0 | 1 | 0 |
| minimalism | A | 94 | 0 | 1 | 3 |
| ux | A | 100 | 0 | 0 | 0 |
| llm_security | N/A | — | 0 | 0 | 0 |

Calcul : 100 moins 25/10/3/1 points par constat CRITICAL/HIGH/MEDIUM/LOW, plancher zéro. Pondérations : sécurité 3; fiabilité, performance, complexité et qualité 2; autres domaines 1. Les constats algorithmiques alimentent le domaine complexité une seule fois. L’absence de constat ne prouve pas une absence universelle de défaut. Le domaine LLM Security ne s’applique pas à ce programme.

## Les cinq corrections prioritaires

1. Valider les arguments des commandes avant les primitives : position Int.min et identifiant de stage vide. Ajouter des tests du routeur complet.
2. Préserver les associations lors de state heal tant que la fermeture n’est pas prouvée. Tester minimisation et changement de Space macOS.
3. Activer exactement la cible affichée. Arrêter un clic si le focus échoue ou si la fenêtre a disparu.
4. Fiabiliser les transitions multi-écrans : restaurer par écran et bureau, respecter --no-follow, utiliser l’écran de la fenêtre visée.
5. Supprimer les recherches répétées des chemins interactifs. Commencer par le contrôle des trous, le plan BSP et les aperçus de groupe. Mesurer ensuite sur les mêmes entrées.

## Tendance

Dernier audit complet trouvé : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-05-09/session-2026-05-09-all-04/scoring.md. Il annonçait A sous v13, sur environ 14 000 lignes et 174 tests. Le présent audit utilise v14, 38 217 lignes et 881 tests inventoriés. Les deux notes ne mesurent pas une évolution à périmètre constant. Aucun delta « corrigé/nouveau » fiable n’est calculable sans fingerprints comparables. Les audits 018 et 020 couvraient seulement leurs sessions. La baseline /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/baseline.json est absente : aucune suppression de constat.

## Session 021 : concurrence, fils d’exécution et fonctions système

Le stockage WindowScanBatch est alloué une fois. Chaque itération de concurrentPerform écrit dans une case distincte. La lecture finale attend la fin du groupe. Aucune course mémoire n’a été démontrée sur ce stockage. Les retours de scan arrivent sur DispatchQueue.main. Les objets de présentation sont isolés par MainActor. Les callbacks utilisent des références faibles et refusent les ajouts après fermeture. Cela ne constitue pas une certification Thread Sanitizer.

La recherche conserve bien la cible sélectionnée. Le défaut de réinterprétation de lettre touche le mode interactif classique. La recherche reste concernée par la fenêtre devenue obsolète avant un clic. Le délai d’attente de focus ne renvoie pas de réussite et le clic peut partir après son expiration. Les tests portent surtout sur les fonctions pures, pas sur cette frontière avec le système.

Les appels AX exécutés en arrière-plan ne sont pas déclarés fautifs par leur seul emplacement. Aucun contrat complet de sûreté multi-thread des applications tierces n’a été vérifié. Les délais de scan n’incluent pas toute la préparation des index AX; aucune latence de bout en bout n’a été mesurée. Les badges ont une recherche de positions quadratique, mais le modèle limite les résultats à 500 : profil à faire avant de chiffrer le coût.

Carbon est appelé depuis un objet MainActor. La résolution des touches est testée. Aucun essai réel de conflit de raccourci, de disposition clavier ou de livraison du callback n’a été fait. Aucun CGEvent n’a été injecté pendant cet audit. Les contrats API consultés servent de référence limitée : [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) et [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent).

## Constats classés du plus grave au moins grave

« Confirmé » signifie prouvé par le chemin de code. Les cinq sondes sont signalées séparément. Cela ne signifie pas que le scénario a été rejoué sur le bureau réel. Les corrections sont proposées, sans application ni validation de compilation de ces corrections.

| ID | Sévérité | Fichier et ligne | Problème |
|---|---|---|---|
| REL-001 | HIGH | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageStore.swift:1135 | Des arguments stage invalides peuvent arrêter le daemon |
| REL-002 | HIGH | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StateAudit.swift:224 | La réparation efface les associations des fenêtres encore ouvertes mais invisibles |
| REL-003 | HIGH | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetModeRuntimeController.swift:152 | Le mode lettres réinterprète la lettre dans une autre liste |
| PERF-001 | HIGH | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:1692 | La validation des trous de disposition parcourt les fenêtres dans chaque cellule |
| PERF-002 | HIGH | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift:28 | Le plan BSP normal reparcourt tout l'arbre pour chaque fenêtre |
| PERF-003 | HIGH | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DropPreviewController.swift:480 | La géométrie de groupe copie et fusionne des suffixes en O(n²) pendant le glisser |
| PERF-004 | HIGH | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:2647 | La réparation de voisinage refait une recherche linéaire pour chaque fenêtre |
| REL-004 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetModeRuntimeController.swift:244 | La grille écran ignore le changement de moniteur demandé par les flèches |
| REL-005 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:394 | Le snapshot d’automatisation perd les noms et les stages vides persistées |
| REL-006 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:1978 | Le tri spatial utilise une relation non transitive |
| REL-007 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:1860 | Les règles de placement ignorent le rôle AX de la fenêtre |
| REL-008 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:1867 | Une règle différée faute d’écran cible n’est jamais retentée |
| REL-009 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:3087 | Les placements de plusieurs écrans empêchent de sauver leurs dispositions |
| DUP-001 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:421 | Le menu recopie trois fois l’exécution et le journal d’une action |
| MIN-001 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailPanel.swift:374 | Le rail recopie des helpers disponibles et conserve un double adaptateur de menu |
| OBS-001 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/FileAdministration.swift:140 | La rotation des logs ouverts coupe leur consultation courante |
| PERF-005 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:1503 | Les commandes répètent des recherches linéaires évitables |
| PERF-006 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:205 | Le menu désactivé déclenche quand même un relevé complet à chaque clic droit |
| REL-010 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieAX/SystemSnapshotProvider.swift:1049 | Le focus annonce un succès lorsque AXRaise échoue sans délai dépassé |
| REL-011 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1702 | Les mauvais types numériques peuvent passer la validation puis devenir des défauts |
| REL-012 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AppTargetQueryService.swift:706 | Le clic part même si la fenêtre cible ne peut plus être focalisée |
| REL-013 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AutomationSnapshotService.swift:101 | La réponse stages ne précise pas l’écran de chaque stage |
| REL-014 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:502 | config reload annonce une application sans changer la configuration du daemon |
| REL-015 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CommandSocketServer.swift:239 | Le PID informatif ne prouve pas que le verrou du daemon est libre |
| REL-016 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DesktopCommands.swift:163 | Déplacer une fenêtre vers son bureau actuel la masque |
| REL-017 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DisplayParkingService.swift:232 | La reconnexion d’un écran fusionne les stages de bureaux différents |
| REL-018 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/EventSubscriptionService.swift:74 | L’abonnement perd des événements lors du remplacement du journal |
| REL-019 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/FocusFollowsMouseController.swift:249 | Le focus souris sélectionne une fenêtre cachée derrière une autre |
| REL-020 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/HiddenWindowPlacement.swift:34 | Un écran placé à gauche est confondu avec une ancienne zone de masquage |
| REL-021 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/JSONPersistence.swift:95 | Une mutation renvoie un succès métier après échec de persistance |
| REL-022 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailController.swift:776 | Le dépôt entre deux rails échoue si leurs stages portent le même identifiant |
| REL-023 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:586 | Le déplacement --no-follow rend visible une stage inactive |
| REL-024 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetMacroService.swift:285 | Le replay avale le relâchement de souris si la cible AX est absente |
| REL-025 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetMacroService.swift:439 | Les macros perdent le bouton droit et les modificateurs souris |
| REL-026 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WidthAdjustmentService.swift:38 | La commande width sélectionne toujours le premier écran |
| REL-027 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WidthAdjustmentService.swift:57 | Les ajustements relatifs utilisent la largeur de la première fenêtre |
| REL-028 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowBookmarkCommands.swift:52 | Focaliser une fenêtre temporairement absente efface son signet |
| REL-029 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowRuleAffinityService.swift:178 | Enregistrer une affinité supprime les autres actions des règles générées |
| REL-030 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/LayoutTypes.swift:74 | La configuration master_ratio n'arrive jamais au moteur de disposition |
| REL-031 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/MasterStackLayoutStrategy.swift:38 | Un espacement trop grand produit une fenêtre hors du conteneur |
| REL-032 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/uninstall:28 | La désinstallation laisse une instance autonome active |
| TEST-001 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/QueryCommandTests.swift:36 | Le test des requêtes vérifie seulement le nom recopié dans la réponse |
| TEST-002 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/TargetModeRuntimeControllerTests.swift:18 | Les tests de cibles ne couvrent pas le raccordement aux effets système |
| TEST-003 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/WindowGroupCommandTests.swift:15 | Le test des commandes de groupe ne contrôle que changed |
| TEST-004 | MEDIUM | /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/WindowGroupIndicatorTests.swift:20 | Le test de l’indicateur de groupe ne couvre aucun rendu réellement utilisé |
| MIN-002 | LOW | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:2075 | Neuf surcharges répètent le même encodeur JSON |
| MIN-003 | LOW | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1620 | Quatre contrôles de plage portent sur des valeurs déjà bornées |
| MIN-004 | LOW | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DesktopCommands.swift:154 | Deux pipelines presque identiques gèrent les déplacements de bureau |
| PERF-007 | LOW | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CommandSocketServer.swift:329 | Le lecteur de ligne réanalyse tout le préfixe à chaque paquet |
| QUAL-001 | LOW | /Users/moi/Nextcloud/10.Scripts/39.roadie/README.fr.md:528 | Les guides décrivent des interactions qui ne correspondent plus au code |

## Détail des constats

### REL-001 — HIGH — Des arguments stage invalides peuvent arrêter le daemon

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageStore.swift:1135

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

La position reçue est diminuée avant son bornage. Int.min - 1 déclenche un arrêt fatal Swift. Le routeur CLI accepte cet entier et le service de commande ne le contrôle pas. Un second chemin atteint une précondition fatale : stage create avec une chaîne vide construit StageID sans vérifier son contenu. Ces deux cas relèvent de la validation des arguments avant appel aux primitives.

Scénario : Avec un écran actif et la stage 1 existante : roadie stage reorder 1 -9223372036854775808. La conversion Int réussit dans /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:988, puis reorderStage calcule Int.min - 1. Ne pas lancer contre le daemon de travail. Autre cas : roadie stage create ''. Aucun de ces appels destructifs n’a été exécuté sur le daemon.

Conséquence : Arrêt du processus qui traite la commande; les services du daemon deviennent indisponibles.

Preuve :

```
    public mutating func reorderStage(_ id: StageID, to position: Int) -> Bool {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return false }
        let stage = stages.remove(at: index)
        let targetIndex = min(max(position - 1, 0), stages.count)
        stages.insert(stage, at: targetIndex)
        return true
    }
```

Correction proposée : Borner la valeur avant toute soustraction. Contrôler aussi les paramètres CLI, mais conserver la protection dans le modèle persistant. Refuser aussi les identifiants vides dans chaque entrée CLI qui construit StageID. Garder les préconditions internes comme garde-fous.

Vérification proposée : Ajouter des cas purs pour Int.min, 0, 1 et Int.max; vérifier un classement valide sans trap et les règles de bornage existantes.

Effort : S. Risque de régression : LOW.

Contre-audit indépendant : CONFIRMED. position - 1 est évalué avant max et min. Sur macOS 64 bits, Int.min - 1 déclenche un arrêt Swift. Le garde de présence du stage ne protège pas la valeur position.

Proposition de code, non appliquée :

```swift
public mutating func reorderStage(_ id: StageID, to position: Int) -> Bool {
    guard let index = stages.firstIndex(where: { $0.id == id }) else { return false }
    let stage = stages.remove(at: index)
    let targetIndex = position <= 1 ? 0 : min(position - 1, stages.count)
    stages.insert(stage, at: targetIndex)
    return true
}

// Dans le cas create du routeur, avant StageCommandService.create :
guard let stageID = args.dropFirst().first, !stageID.isEmpty else {
    err("roadie: stage create requires a nonempty stage id")
    return 64
}
```

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:985

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:340

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Identifiers.swift:33

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:971

### REL-002 — HIGH — La réparation efface les associations des fenêtres encore ouvertes mais invisibles

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StateAudit.swift:224

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

heal construit liveWindowIDs uniquement depuis les fenêtres présentes dans le relevé à l’écran. repairScopes supprime ensuite tout membre absent sans vérifier sa fermeture ni garder la grâce de réconciliation. Le relevé ne réintroduit pas les fenêtres minimisées ou sur un autre Space.

Scénario : Associer une fenêtre à un stage distinct du stage actif, puis minimiser cette fenêtre (ou changer de Space macOS). Exécuter roadie state heal, puis réafficher la fenêtre : son ancien membre a été supprimé. Le chemin CLI appelle StateAuditService.heal à /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:347.

Conséquence : Perte persistante de l’association fenêtre/stage et de sa place dans le groupe ; la commande annoncée comme conservatrice traite une absence temporaire comme une fermeture.

Preuve :

```
            for stageIndex in state.scopes[scopeIndex].stages.indices {
                let beforeCount = state.scopes[scopeIndex].stages[stageIndex].members.count
                state.scopes[scopeIndex].stages[stageIndex].members.removeAll { member in
                    if !liveWindowIDs.contains(member.windowID) {
                        return true
                    }
                    if seenWindowIDs.contains(member.windowID) {
                        return true
```

Correction proposée : Conserver un membre absent tant que sa fermeture n’est pas prouvée. Réutiliser la preuve AX de destruction ou, au minimum, vérifier que son PID est mort. Garder la déduplication indépendante de la visibilité.

Vérification proposée : Ajouter un test avec un membre PID vivant absent de provider.windows : après heal, appartenance, ordre et focus persistent. Ajouter un cas PID prouvé mort et un cas doublon.

Effort : S. Risque de régression : MEDIUM.

Contre-audit indépendant : CONFIRMED. repairScopes retire immédiatement chaque membre absent de liveManagedWindowIDs. Le fournisseur ne relève que les fenêtres on-screen. SnapshotService préserve les absents trente minutes dans les membres persistants mais ne les ajoute pas aux ScopedWindowSnapshot. Cette préservation amont ne protège donc pas heal.

Proposition de code, non appliquée :

```swift
state.scopes[scopeIndex].stages[stageIndex].members.removeAll { member in
    if !liveWindowIDs.contains(member.windowID),
       let pid = member.pid, !ProcessLiveness.isAlive(pid) {
        return true
    }
    return !seenWindowIDs.insert(member.windowID).inserted
}
```

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieAX/SystemSnapshotProvider.swift:612

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:415

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonHealth.swift:117

### REL-003 — HIGH — Le mode lettres réinterprète la lettre dans une autre liste

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetModeRuntimeController.swift:152

Statut : confirmé par lecture du code. Correction : non appliquée.

L'overlay attribue ses lettres à la liste choisie par source, filtre et includeAppTargets. La fermeture activate transmet seulement la lettre à TargetHintService.activate(String), qui reconstruit une liste source=.all sans reprendre ces options (/Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetHintService.swift:384). La lettre affichée ne désigne donc plus nécessairement la cible activée. Le mode recherche 021 utilise déjà la surcharge activate(target:) qui évite ce problème.

Scénario : Activer experimental.target_mode.overlay_enabled. Ouvrir une application avec un bouton Accessibility. Lancer roadie targets interactive --source app --include-app-targets, puis taper A, lettre du premier bouton affiché. La nouvelle liste source=.all commence par l'écran : le focus porte sur celui-ci, ou --action click renvoie unsupported_action. Un filtre qui réduit la liste à une fenêtre produit le même décalage.

Conséquence : Une interaction usuelle active un autre objet que celui affiché. Les options source, filtre et inclusion applicative perdent leur sens à la validation.

Preuve :

```
        currentSession = TargetOverlayPresenter.startInteractive(
            overlay,
            duration: duration,
            activate: { label in
                targets.activate(label, action: action)
            },
            onFinish: { [weak self] result in
                self?.finish(result, command: command.name)
            }
```

Correction proposée : Résoudre la lettre dans overlay.report.targets conservé par la session, puis appeler targets.activate(target:action:). Ne pas relire et réétiqueter les fenêtres lors de la validation.

Vérification proposée : Injecter deux listes de sources différentes et un fournisseur espion. Pour une liste applicative où A est un bouton, vérifier que la validation A transmet exactement l'identifiant du bouton. Ajouter un cas filtré et un cas includeAppTargets=true/config.enabled=false.

Effort : S. Risque de régression : MEDIUM.

Contre-audit indépendant : CONFIRMED. Le contrôleur conserve options pour construire overlay, mais transmet seulement label à activate(String). Cette méthode reconstruit source all sans filtre et avec includeAppTargets issu de la configuration. Les écrans sont ajoutés avant les cibles applicatives. La première lettre applicative peut donc sélectionner un écran.

Proposition de code, non appliquée :

```swift
activate: { label in
    guard let selected = overlay.report.targets.first(where: {
        $0.label.caseInsensitiveCompare(label) == .orderedSame
    }) else {
        return TargetActionResult(
            changed: false,
            message: "unknown_target: \(label)",
            error: "unknown_target"
        )
    }
    return targets.activate(target: selected, action: action)
},
```

### PERF-001 — HIGH — La validation des trous de disposition parcourt les fenêtres dans chaque cellule

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:1692

Statut : confirmé par lecture; pas de reproduction macOS exécutée. Correction : non appliquée.

Les bords X et Y ont chacun O(n) valeurs. Le produit de ces axes crée O(n²) cellules. Pour chaque cellule, frames.contains parcourt jusqu'à n cadres. Les intentions de commande contournent le minimum de taille des tuiles (1620–1622), et aucune limite du nombre de fenêtres n'est imposée.

Scénario : Créer un intent .command sans gap avec n=2m fenêtres : m colonnes de largeur 100, hauteur totale 50*(m+1). Dans la colonne i (0..<m), une fenêtre couvre y=0..50*(i+1), l'autre couvre y=50*(i+1)..hauteur. Toutes les cellules sont couvertes et mesurent 100x50 : le retour anticipé ne s'active jamais. Sauver cet intent puis appeler hasValidLayoutIntent ou applyPlan.

Conséquence : Coût cubique confirmé par les boucles. Cette validation appartient au maintien de disposition via /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:633 et 3104. La latence pratique n'a pas été mesurée.

Preuve :

```
            for yIndex in 0..<max(0, yEdges.count - 1) {
                let minY = yEdges[yIndex]
                let maxY = yEdges[yIndex + 1]
                let height = maxY - minY
                guard height > tolerance else { continue }
                let cell = CGRect(x: minX, y: minY, width: width, height: height)
                guard container.contains(cell, tolerance: 1),
                      !frames.contains(where: { frameContainsCellCenter($0, cell: cell, tolerance: 1) })
                else { continue }
                return true
```

Correction proposée : Calculer une seule fois la couverture des centres de cellules. Le tableau de différences ci-dessous supprime le parcours des n cadres pour chaque cellule, en conservant les mêmes seuils. Mesurer avant de choisir entre cette grille O(n²) mémoire et un balayage d'intervalles.

Vérification proposée : Comparer l'ancienne et la nouvelle fonction sur des dispositions complètes, trouées et à marges. Ajouter la famille de colonnes décrite avec m croissant et compter les comparaisons. Compiler la proposition avant intégration.

Effort : S. Risque de régression : MEDIUM.

Contre-audit indépendant : CONFIRMED. framesLeaveLargeUntiledCells combine les bords X et Y puis appelle frames.contains pour chaque cellule assez grande. La famille de colonnes scindées à des hauteurs différentes décrite par l’auditeur couvre toutes les cellules, donc ne déclenche aucune sortie anticipée et atteint O(n³).

Mesure et retour arrière : Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse. Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.

Proposition de code, non appliquée :

```swift
private func framesLeaveLargeUntiledCells(
    _ frames: [CGRect], in container: CGRect, allowedGap: CGFloat
) -> Bool {
    guard frames.count > 1 else { return false }
    let tolerance = max(LayoutTolerance.untiledCell, allowedGap)
    let xs = sortedEdges([container.minX, container.maxX] + frames.flatMap { [$0.minX, $0.maxX] })
    let ys = sortedEdges([container.minY, container.maxY] + frames.flatMap { [$0.minY, $0.maxY] })
    let nx = max(0, xs.count - 1), ny = max(0, ys.count - 1)
    guard nx > 0, ny > 0 else { return false }
    let xc = (0..<nx).map { (xs[$0] + xs[$0 + 1]) / 2 }
    let yc = (0..<ny).map { (ys[$0] + ys[$0 + 1]) / 2 }
    func bound(_ values: [CGFloat], _ target: CGFloat, upper: Bool) -> Int {
        var lo = 0, hi = values.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if values[mid] < target || (upper && values[mid] == target) { lo = mid + 1 }
            else { hi = mid }
        }
        return lo
    }
    // Différences de couverture, puis sommes cumulées : O(n² + n log n).
    let stride = ny + 1
    var coverage = Array(repeating: 0, count: (nx + 1) * stride)
    for frame in frames {
        let x0 = bound(xc, frame.minX - 1, upper: false)
        let x1 = bound(xc, frame.maxX + 1, upper: true)
        let y0 = bound(yc, frame.minY - 1, upper: false)
        let y1 = bound(yc, frame.maxY + 1, upper: true)
        guard x0 < x1, y0 < y1 else { continue }
        coverage[x0 * stride + y0] += 1
        coverage[x1 * stride + y0] -= 1
        coverage[x0 * stride + y1] -= 1
        coverage[x1 * stride + y1] += 1
    }
    for x in 0..<nx {
        for y in 0..<ny {
            let index = x * stride + y
            if x > 0 { coverage[index] += coverage[(x - 1) * stride + y] }
            if y > 0 { coverage[index] += coverage[index - 1] }
            if x > 0 && y > 0 { coverage[index] -= coverage[(x - 1) * stride + y - 1] }
            let cell = CGRect(x: xs[x], y: ys[y], width: xs[x + 1] - xs[x], height: ys[y + 1] - ys[y])
            if coverage[index] == 0, cell.width > tolerance, cell.height > tolerance,
               container.contains(cell, tolerance: 1) { return true }
        }
    }
    return false
}
```

### PERF-002 — HIGH — Le plan BSP normal reparcourt tout l'arbre pour chaque fenêtre

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/SpatialBSPLayoutStrategy.swift:28

Statut : confirmé par lecture et analyse des parcours. Correction : non appliquée.

Même lorsque toutes les fenêtres ont déjà une feuille, chaque élément de windows déclenche tree.contains, qui parcourt l'arbre. Le plan ordinaire est donc quadratique. De plus, BSPTree.windowIDs concatène les tableaux de chaque sous-arbre ; cet accès annoncé O(n) peut être O(n²) pour un arbre en chaîne. Le coût des insertions de secours n'est pas la seule cause.

Scénario : Prendre un arbre contenant n fenêtres et appeler plan avec exactement ces n identifiants. Aucune insertion n'est faite, mais n recherches linéaires sont effectuées. Un arbre construit par insertions successives sur la dernière fenêtre ajoute aussi les copies récursives de windowIDs.

Conséquence : Travail évitable dans chaque calcul de disposition. Aucune latence absolue n'a été mesurée ; la sévérité HIGH découle de l'Article XVIII, pas d'un gel observé.

Preuve :

```
        var tree = full.projected(excluding: Set(full.windowIDs).subtracting(requested))
        var previous: WindowID?
        for id in windows where !tree.contains(id) {
            tree = tree.inserting(id, at: previous, side: .right, in: rect, innerGap: gap)
            previous = id
        }
```

Correction proposée : Collecter les feuilles dans un seul accumulateur. Préparer un Set des identifiants présents avant la boucle. Garder l'ordre et l'ancre actuels pour les insertions réellement nécessaires.

Vérification proposée : Conserver les tests de SpatialBSPLayoutStrategyTests ; comparer les placements avant/après pour un arbre complet, une projection et des fenêtres manquantes. Mesurer séparément le chemin sans insertion à plusieurs tailles. Le code de correction fourni n'a pas été compilé dans cette tâche.

Effort : S. Risque de régression : LOW.

Contre-audit indépendant : CONFIRMED. tree.contains parcourt récursivement l’arbre. Avec les n feuilles déjà présentes, la boucle appelle cette recherche n fois sans aucune insertion : complexité quadratique. windowIDs concatène aussi les sous-tableaux ; sur un arbre en chaîne, ses copies peuvent être quadratiques.

Mesure et retour arrière : Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse. Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.

Proposition de code, non appliquée :

```swift
// Remplacement de BSPTree.windowIDs
public var windowIDs: [WindowID] {
    var result: [WindowID] = []
    func collect(_ node: BSPTree) {
        switch node {
        case .empty: break
        case .leaf(let id): result.append(id)
        case .split(_, _, let first, let second):
            collect(first)
            collect(second)
        }
    }
    collect(self)
    return result
}

// Remplacement de SpatialBSPLayoutStrategy.plan
public func plan(_ request: LayoutRequest) -> LayoutPlan {
    let windows = request.windowIDs
    guard !windows.isEmpty else { return LayoutPlan(placements: [:]) }
    let rect = request.container.inset(by: request.outerGaps)
    let gap = CGFloat(request.innerGap)
    let requested = Set(windows)
    let full = request.bspTree ?? .empty
    var tree = full.projected(excluding: Set(full.windowIDs).subtracting(requested))
    var present = Set(tree.windowIDs)
    var previous: WindowID?
    for id in windows where present.insert(id).inserted {
        tree = tree.inserting(id, at: previous, side: .right, in: rect, innerGap: gap)
        previous = id
    }
    return LayoutPlan(placements: tree.place(in: rect, innerGap: gap))
}
```

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/BSPTree.swift:54

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/BSPTree.swift:65

### PERF-003 — HIGH — La géométrie de groupe copie et fusionne des suffixes en O(n²) pendant le glisser

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DropPreviewController.swift:480

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

Chaque appel récursif construit un nouveau tableau de n−1 fenêtres puis fusionne un dictionnaire de n−1 placements. La somme des tailles traitées est quadratique. La chaîne candidate → structuralPlacements → planGroup reste active pour bsp/masterStack. activeEntries vient de toutes les fenêtres de la stage, sans plafond explicite. La même implémentation apparaît dans /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowCommands.swift:1159. Les deux sites sont regroupés dans ce constat.

Scénario : Utiliser bsp ou masterStack avec plusieurs fenêtres redimensionnables dans la même stage. Glisser une fenêtre vers le bord d’une autre, avec au moins une fenêtre dans chaque groupe géométrique. Chaque mise à jour d’aperçu calcule planGroup. Augmenter la taille du groupe augmente le nombre de copies et de fusions selon n(n−1)/2.

Conséquence : Travail quadratique et profondeur de pile linéaire dans les mises à jour du glisser. La dégradation effective de latence reste à mesurer. Le mode spatialBsp emprunte un autre chemin.

Preuve :

```
    private func planGroup(_ windowIDs: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        guard let first = windowIDs.first else { return [:] }
        guard windowIDs.count > 1 else { return [first: rect.integral] }

        let parts = split(rect, horizontally: horizontal, gap: gap, firstCount: 1, secondCount: windowIDs.count - 1)
        var placements = [first: parts.first.integral]
        placements.merge(planGroup(Array(windowIDs.dropFirst()), in: parts.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        return placements
```

Correction proposée : Conserver un rectangle restant, une orientation et un index. Ajouter chaque placement directement dans un seul dictionnaire. Cette passe réalise les mêmes découpes en O(n).

Vérification proposée : Comparer les rectangles de la version récursive et de la version itérative pour n=0,1,2,3,10,100, orientations et gaps variés. Vérifier que les changements d’orientation et les arrondis restent identiques. Mesurer séparément le temps d’aperçu.

Effort : M. Risque de régression : MEDIUM.

Contre-audit indépendant : CONFIRMED. Chaque niveau construit Array(dropFirst()) puis fusionne les n−1 résultats suivants. La somme des tailles copiées et fusionnées est quadratique. Le contrôleur recalcule candidate sur les événements de déplacement avant de comparer à lastCandidate.

Mesure et retour arrière : Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse. Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.

Proposition de code, non appliquée :

```swift
private func planGroup(_ windowIDs: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
    var placements: [WindowID: CGRect] = [:]
    placements.reserveCapacity(windowIDs.count)
    var remainingRect = rect
    var isHorizontal = horizontal
    for (index, windowID) in windowIDs.enumerated() {
        let remainingCount = windowIDs.count - index
        let frame: CGRect
        if remainingCount == 1 {
            frame = remainingRect.integral
        } else {
            let parts = split(remainingRect, horizontally: isHorizontal, gap: gap,
                              firstCount: 1, secondCount: remainingCount - 1)
            frame = parts.first.integral
            remainingRect = parts.second
            isHorizontal.toggle()
        }
        if placements[windowID] == nil { placements[windowID] = frame }
    }
    return placements
}
```

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DropPreviewController.swift:181

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DropPreviewController.swift:389

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowCommands.swift:1159

### PERF-004 — HIGH — La réparation de voisinage refait une recherche linéaire pour chaque fenêtre

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:2647

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

clampedSiblingRepairPlan filtre les n IDs du stage avec contains sur les m fenêtres voisines. Cette intersection coûte O(n*m), alors qu’un Set conserve exactement l’ordre et le résultat en O(n+m). Le code est atteint lors d’un refus de taille des modes sans arbre ; aucune borne de nombre de fenêtres n’est imposée ici.

Scénario : Utiliser un stage bsp ou masterStack avec n fenêtres, dont une refuse la taille demandée. Chaque appel de réparation recherche chaque ID dans siblingEntries ; avec n voisins, le nombre de comparaisons croît au carré.

Conséquence : Travail CPU évitable dans une passe synchrone du tiler. Aucun retard en millisecondes n’a été mesuré ; le constat porte sur la classe de complexité.

Preuve :

```
            guard !siblingEntries.isEmpty else { continue }
            let siblingIDs = stage.windowIDs.filter { id in
                siblingEntries.contains { $0.window.id == id }
            }
            guard !siblingIDs.isEmpty else { continue }
```

Correction proposée : Construire un Set des IDs voisins une fois avant le filtre.

Vérification proposée : Comparer le résultat et son ordre sur 10, 100 et 1000 fenêtres synthétiques. Mesurer le nombre de recherches ou le temps de la seule intersection. Revenir à l’ancien filtre si le résultat diffère.

Effort : S. Risque de régression : MEDIUM.

Contre-audit indépendant : CONFIRMED. La recherche répétée est bien en O(n*m). Aucun garde du chemin ni StageState.insert ne borne le nombre d’identifiants. Le Set proposé préserve le résultat et son ordre. La branche est conditionnelle dans le fonctionnement interactif ; sa fréquence réelle et sa latence ne sont pas mesurées.

Mesure et retour arrière : Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse. Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.

Proposition de code, non appliquée :

```swift
let siblingIDSet = Set(siblingEntries.map(\.window.id))
let siblingIDs = stage.windowIDs.filter { siblingIDSet.contains($0) }
guard !siblingIDs.isEmpty else { continue }
```

### REL-004 — MEDIUM — La grille écran ignore le changement de moniteur demandé par les flèches

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetModeRuntimeController.swift:244

Statut : confirmé par lecture du code. Correction : non appliquée.

startGridInteractive fige systématiquement une racine, y compris pour scope=display. stateProvider et activate utilisent cette racine dès qu'elle existe, sans tenir compte de selectedDisplayIndex. TargetGridInteractiveSession.moveDisplay modifie pourtant ce dernier à chaque flèche au niveau racine.

Scénario : Avec deux écrans, lancer roadie grid interactive --scope display --display 1. Au niveau racine, taper la flèche vers l'écran 2. displayIndex devient 2 mais la grille reste produite depuis frozenRoot de l'écran 1 ; choisir une cellule puis Espace clique encore dans l'écran 1.

Conséquence : La navigation entre écrans décrite dans les documentations française et anglaise ne fonctionne pas. Le journal peut annoncer le nouvel écran alors que l'action reste sur l'ancien.

Preuve :

```
            stateProvider: { selectedDisplayIndex, parentPath in
                if let frozenRoot {
                    return TargetOverlayState(
                        visible: true,
                        labelsOnly: true,
                        report: grid.targets(root: frozenRoot, parentPath: parentPath)
                    )
                }
```

Correction proposée : Réserver la racine figée à scope=focusedWindow, ou mettre à jour une racine de session lors du changement d'écran. L'affichage et l'action doivent utiliser la même racine actuelle.

Vérification proposée : Créer deux DisplaySnapshot, simuler la flèche à la racine, puis vérifier displayId et cadre des cibles ainsi que le point final de clic.

Effort : S. Risque de régression : MEDIUM.

### REL-005 — MEDIUM — Le snapshot d’automatisation perd les noms et les stages vides persistées

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:394

Statut : confirmé par lecture de la chaîne snapshot -> automationSnapshot -> query; aucun test exécuté. Correction : non appliquée.

La réconciliation reconstruit RoadieState avec des noms génériques, sans label de desktop. Elle crée la stage active et les stages rencontrées dans les fenêtres visibles. Les stages inactives vides, même nommées, ne sont pas transférées. AutomationSnapshotService lit ce RoadieState pour les réponses stages/desktops sans compléter ces métadonnées depuis StageStore.

Scénario : Configurer StageDefinition(id: "1", displayName: "Work") et StageDefinition(id: "2", displayName: "Com"), sans fenêtre et stage 1 active. Le store contient les deux noms (test SnapshotServiceTests:943–967), mais SnapshotService.snapshot().automationSnapshot().stages ne contient que Stage 1, avec le nom générique. Même perte après renommage d’une stage ou label d’un desktop.

Conséquence : Les clients query state/stages/desktops obtiennent des noms inexacts et une liste incomplète des espaces configurés. Une interface d’automatisation ne peut pas proposer toutes les destinations existantes.

Preuve :

```
            let activePersistentStage = persistentScope.stages.first { $0.id == persistentScope.activeStageID }
            let activeMode = activePersistentStage?.mode ?? config.tiling.defaultStrategy
            try? state.createStage(
                id: persistentScope.activeStageID,
                name: "Stage \(persistentScope.activeStageID.rawValue)",
                mode: activeMode,
                in: display.id,
                desktopID: currentDesktopID
            )
```

Correction proposée : Construire la hiérarchie runtime depuis les scopes, noms, labels et stages persistés avant d’y associer les fenêtres live. Garder séparés les membres absents et les métadonnées toujours valides. Une alternative est de compléter uniquement le modèle automation depuis le même état persisté cohérent.

Vérification proposée : Étendre le test configWorkspacesSeedPersistentStageNames pour vérifier le snapshot automation, les deux stages nommées sans fenêtres, un desktop nommé et une stage renommée. Ne pas se limiter au store.

Effort : M. Risque de régression : MEDIUM.

### REL-006 — MEDIUM — Le tri spatial utilise une relation non transitive

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:1978

Statut : confirmé par lecture; pas de reproduction macOS exécutée. Correction : non appliquée.

Le tri change d'axe selon l'écart entre deux centres. Une tolérance de proximité ne définit pas une classe d'équivalence transitive. Le mode bsp appelle ce comparateur via orderedWindowIDs et spatiallyOrdered.

Scénario : Avec un conteneur horizontal et trois fenêtres A=(centre 500,600), B=(540,550), C=(580,500), seuil spatialAlignment=48 : B<A par Y, C<B par Y, mais A<C par X. Le cycle viole le contrat de tri.

Conséquence : L'ordre spatial calculé dépend du parcours du tri et peut déplacer les fenêtres de façon incohérente. Le cycle de comparaison est confirmé par le code. Aucun crash ou saut visuel n'a été reproduit.

Preuve :

```
        if horizontal {
            if abs(lhsFrame.midX - rhsFrame.midX) > LayoutTolerance.spatialAlignment {
                return lhsFrame.midX < rhsFrame.midX
            }
            if abs(lhsFrame.midY - rhsFrame.midY) > LayoutTolerance.spatialAlignment {
                return lhsFrame.midY < rhsFrame.midY
            }
        } else {
```

Correction proposée : Définir un ordre total : soit comparer les centres lexicographiquement sans seuil, soit former les bandes spatiales une fois puis trier par clé de bande, centre secondaire et ID.

Vérification proposée : Ajouter un test de transitivité pour le triplet ci-dessus et ses permutations. Le test public peut comparer orderedWindowIDs sur [A,B], [B,C] et [A,C] avec mode .bsp, même conteneur horizontal et RoadieState reconstruit pour chaque paire.

Effort : S. Risque de régression : MEDIUM.

### REL-007 — MEDIUM — Les règles de placement ignorent le rôle AX de la fenêtre

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:1860

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

Le contexte passé au moteur de règles ne renseigne ni role ni subrole. WindowRuleMatcher compare ces critères uniquement avec le contexte, sans reprendre les champs de window. Une règle de placement qui impose role ou subrole ne correspond donc jamais dans le maintainer.

Scénario : Définir une règle app="Terminal", role="AXWindow", assign_stage="dev", puis ouvrir une nouvelle fenêtre Terminal de rôle AXWindow. La policy du snapshot peut reconnaître le rôle mais evaluateRules reçoit context.role=nil et ne place pas la fenêtre.

Conséquence : Les critères exposés par la configuration et par rules explain n’ont pas le même comportement que le placement réel.

Preuve :

```
        for entry in snapshot.windows where entry.window.isOnScreen {
            let context = WindowRuleMatchContext(
                display: entry.scope?.displayID.rawValue,
                desktop: entry.scope.map { String($0.desktopID.rawValue) },
                stage: entry.scope?.stageID.rawValue
            )
            let application = ruleEngine.evaluate(window: entry.window, context: context)
```

Correction proposée : Renseigner role: entry.window.role et subrole: entry.window.subrole lors de la création du contexte. Définir et transmettre aussi la source réelle d’isFloating au lieu de laisser ce critère toujours nil.

Vérification proposée : Tester LayoutMaintainer avec une fenêtre dont le rôle est réellement renseigné et une règle role/subrole, puis un rôle différent. Éviter un test limité au matcher recevant un contexte construit à la main.

Effort : S. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowRuleMatcher.swift:42

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:827

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/WindowRuleMatcherTests.swift:23

### REL-008 — MEDIUM — Une règle différée faute d’écran cible n’est jamais retentée

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:1867

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

evaluateRules inscrit systématiquement la fenêtre dans observedRulePlacementWindowIDs, même quand applyRulePlacement renvoie nil pour destination indisponible. Aux passes suivantes, la garde window already managed intervient avant de résoudre à nouveau la destination.

Scénario : Ouvrir une fenêtre correspondant à assign_display="External" alors que l’écran External est débranché. La première passe publie rule.placement_deferred. Rebrancher External en gardant la fenêtre ouverte et visible : son ID reste observé et la règle est désormais ignorée.

Conséquence : Le placement annoncé comme différé est abandonné jusqu’à disparition puis réapparition de la fenêtre dans le relevé ou redémarrage du maintainer.

Preuve :

```
            appendRuleEvents(application, window: entry.window)
            if let placement = applyRulePlacement(application, entry: entry, snapshot: snapshot) {
                placements.append(placement)
            }
            observedRulePlacementWindowIDs.insert(entry.window.id)
        }
```

Correction proposée : Distinguer une décision définitive d’une décision deferred. Ne marquer l’ID traité qu’après un placement ou un refus définitif ; retenter une destination indisponible au changement de topologie.

Vérification proposée : Étendre tickDefersPlacementWhenDisplayIsMissing : ajouter ensuite l’écran à un fournisseur mutable, avancer le délai de stabilisation et vérifier le placement.

Effort : S. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:2043

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:2088

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/WindowRuleMaintainerTests.swift:540

### REL-009 — MEDIUM — Les placements de plusieurs écrans empêchent de sauver leurs dispositions

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:3087

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

persistLayoutIntent initialise les placements d’un seul scope puis ajoute toutes les fenêtres appliquées sur tous les scopes. La garde compare ensuite cet ensemble pollué aux seuls IDs du stage. Elle abandonne dès qu’une autre fenêtre a été placée ailleurs pendant la même passe.

Scénario : Préparer deux écrans avec des stages bsp ou masterStack sans intent, chacun nécessitant une écriture. Lancer une passe qui réussit sur les deux écrans. Pour chaque scope, resultFrames contient aussi les IDs de l’autre ; aucune disposition de cette passe n’est sauvegardée.

Conséquence : La mémorisation des dispositions varie selon les écritures simultanées sur un autre écran. Une commande de masquage d’un stage inactif suffit également à introduire un ID étranger.

Preuve :

```
            var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
                guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
                return (entry.window.id, entry.window.frame)
            })
            for (id, frame) in resultFrames {
                placements[id] = frame
            }
            guard Set(placements.keys) == Set(stage.windowIDs) else { continue }
            service.saveLayoutIntent(scope: scope, windowIDs: stage.windowIDs, placements: placements)
```

Correction proposée : Ne fusionner que les resultFrames des IDs du scope courant. Grouper les résultats par scope en amont pour éviter de reparcourir tout le résultat pour chaque scope.

Vérification proposée : Test de deux écrans avec placements simultanés : chaque intent doit contenir uniquement ses membres et toutes ses frames appliquées.

Effort : S. Risque de régression : MEDIUM.

Proposition de code, non appliquée :

```swift
for id in placements.keys {
    if let frame = resultFrames[id] { placements[id] = frame }
}
```

### DUP-001 — MEDIUM — Le menu recopie trois fois l’exécution et le journal d’une action

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:421

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

Les trois constructeurs de menus recréent la même closure : construire WindowContextAction, appeler execute, puis publier les mêmes champs de résultat. Seul le type de destination change. Leur raison de changer est commune et une extraction locale suffit.

Scénario : Lors d’une évolution de l’événement titlebar_context_menu.action ou du traitement d’un échec, modifier seulement l’un des trois constructeurs produit trois comportements différents selon le sous-menu.

Conséquence : Charge de maintenance évitable et risque de divergence entre actions ordinaires, destinations et desktop/stage.

Preuve :

```
        let target = TitlebarMenuActionTarget { [weak self] targetID in
            guard let self else { return }
            let action = WindowContextAction(windowID: windowID, kind: kind, targetID: targetID, sourceScope: sourceScope)
            let result = self.actions.execute(action)
            self.events.append(RoadieEvent(
                type: result.changed ? "titlebar_context_menu.action" : "titlebar_context_menu.failed",
                scope: sourceScope,
                details: [
                    "windowID": String(windowID.rawValue),
                    "kind": kind.rawValue,
```

Correction proposée : Extraire une méthode privée executeAndLog(_ action: WindowContextAction). Garder la construction des menus et leurs filtres distincts.

Vérification proposée : Vérifier un événement identique pour les trois familles de menu avec succès et échec.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:457

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:506

### MIN-001 — MEDIUM — Le rail recopie des helpers disponibles et conserve un double adaptateur de menu

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailPanel.swift:374

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

action, stageID et stageDragPayload refont le parcours déjà fourni par stageCard(at:). StageCardView recalcule la mosaïque dans hitPreviewItems malgré mosaicPreviewFrames utilisé au rendu. RailStageRenameMenuTarget est identique à RailMenuActionTarget. Aucune contrainte de compatibilité ou justification de séparation n’est indiquée aux sites ou dans les ADR lus.

Scénario : Une modification de la zone cliquable ou de la géométrie de mosaïque doit être répétée dans le rendu et le hit-test. Les helpers privés actuels permettent déjà de partager ces calculs.

Conséquence : Environ 80 lignes supprimables sans nouvelle couche : ~30 pour les hit-tests du panneau, ~25 pour la mosaïque/icônes, ~15 pour le double adaptateur, ~10 pour les délégations et variables redondantes adjacentes. Estimation de refactor, pas diff exécuté.

Preuve :

```
        guard let contentView, acceptsRailInteraction(at: screenPoint) else { return nil }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(contentPoint)
        while let current = view {
            if let card = current as? StageCardView {
                let local = card.convert(contentPoint, from: contentView)
                return card.action(at: local)
            }
            view = current.superview
```

Correction proposée : Réutiliser stageCard(at:), mosaicPreviewFrames(in:) et iconPreviewFrames(in:). Employer RailMenuActionTarget pour Renommer. Supprimer le relais hitPreviewItemsFrontToBack en déplaçant son commentaire utile sur hitPreviewItems.

Vérification proposée : Conserver les résultats de hit-test et la géométrie pour chaque mode, y compris les cartes vides et les bords. Compiler pour vérifier les sélecteurs Objective-C.

Effort : S. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCardView.swift:669

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailController.swift:1293

### OBS-001 — MEDIUM — La rotation des logs ouverts coupe leur consultation courante

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/FileAdministration.swift:140

Statut : confirmé par lecture. Correction : non appliquée.

Le nettoyage renomme stdout et stderr en .1. Le daemon conserve ses descripteurs ouverts vers le même fichier renommé. Aucun code ne rouvre les sorties. Les lectures via scripts/logs et les nettoyages suivants inspectent uniquement le nom sans suffixe.

Scénario : Avec un daemon lancé par launchd et un log supérieur au seuil, exécuter cleanup --apply. La sortie suivante du daemon est ajoutée dans .log.1. Le chemin .log a disparu et les nettoyages suivants ne bornent plus le fichier qui continue de grossir.

Conséquence : Le diagnostic courant perd les nouvelles traces. La rotation cesse de limiter la taille du log de cette instance.

Preuve :

```
            if !dryRun {
                let backup = URL(fileURLWithPath: "\(url.path).1")
                try? manager.removeItem(at: backup)
                action.applied = (try? manager.moveItem(at: url, to: backup)) != nil
            }
            return action
```

Correction proposée : Choisir une rotation compatible avec les descripteurs ouverts. Prévoir une réouverture explicite coordonnée avec le daemon, ou une copie puis troncature documentée avec ses limites. N’annoncer la rotation réussie que lorsque les nouvelles écritures vont vers le journal courant.

Vérification proposée : Test avec un descripteur déjà ouvert : écrire, lancer la rotation, réécrire avec le même descripteur, puis vérifier que le lecteur courant voit la nouvelle ligne et que les rotations suivantes fonctionnent.

Effort : M. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/install:126

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/logs:4

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/FileAdministrationTests.swift:59

### PERF-005 — MEDIUM — Les commandes répètent des recherches linéaires évitables

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:1503

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

Le filtrage des stages restantes fait contains sur la liste visible pour chaque candidate. Deux autres helpers de dépôt font le même type de recherche répétée dans scopedIDs ou ordered. Les listes n’ont pas de borne appliquée dans le code.

Scénario : Appeler stage assign-position sur un scope comportant s stages visibles : chaque candidate parcourt visible. Les helpers de dépôt répètent le motif pour les identifiants de fenêtres.

Conséquence : Coût O(s²) au lieu de O(s) pour une opération simple; pas de latence mesurée et charge limitée en usage ordinaire.

Preuve :

```
    private func stageID(atAssignablePosition position: Int, in scope: PersistentStageScope) -> StageID? {
        let candidates = scope.stages.filter(isSelectableStage)
        let visible = candidates.filter { !$0.members.isEmpty }.map(\.id)
        let remaining = candidates.map(\.id).filter { !visible.contains($0) }
        let ordered = visible + remaining
        let index = position - 1
        guard ordered.indices.contains(index) else { return nil }
        return ordered[index]
```

Correction proposée : Filtrer directement les stages vides; convertir scopedIDs et ordered en Set avant leurs boucles. Conserver l’ordre original dans les tableaux.

Vérification proposée : Vérifier le même ordre pour stages vides, non vides et parkées. Contrôler par lecture qu’aucun contains linéaire ne reste dans les boucles de ces trois helpers.

Effort : S. Risque de régression : LOW.

Mesure et retour arrière : Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse. Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.

Proposition de code, non appliquée :

```swift
private func stageID(atAssignablePosition position: Int, in scope: PersistentStageScope) -> StageID? {
    guard position > 0 else { return nil }
    let candidates = scope.stages.filter(isSelectableStage)
    let visible = candidates.filter { !$0.members.isEmpty }.map(\.id)
    let remaining = candidates.filter { $0.members.isEmpty }.map(\.id)
    let ordered = visible + remaining
    let index = position - 1
    guard ordered.indices.contains(index) else { return nil }
    return ordered[index]
}
```

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:1398

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:1448

### PERF-006 — MEDIUM — Le menu désactivé déclenche quand même un relevé complet à chaque clic droit

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:205

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

start installe ses deux moniteurs sans garde enabled. handleRightMouseDown appelle snapshot avant hitTest, seule fonction qui refuse le mode désactivé. snapshot interroge provider.windows et réconcilie l’état; ce travail tourne sur MainActor.

Scénario : Conserver experimental.titlebar_context_menu.enabled=false, valeur par défaut. Démarrer le daemon standard sans --no-titlebar-menu. Faire un clic droit dans une autre application : le moniteur global appelle snapshot avant de conclure disabled.

Conséquence : Coût Accessibility et accès aux fichiers inutiles sur le fil de l’interface. Aucune latence en millisecondes n’a été mesurée.

Preuve :

```
    public func handleRightMouseDown(at point: CGPoint, source: String = "unknown") -> Bool {
        let settings = TitlebarContextMenuSettings(config: configLoader().experimental.titlebarContextMenu)
        let snapshot = snapshotService.snapshot()
        let axPoint = Self.appKitPointToAX(point)
        let hit = Self.hitTest(point: axPoint, snapshot: snapshot, settings: settings)
        traceClick(source: source, rawPoint: point, axPoint: axPoint, hit: hit, snapshot: snapshot, settings: settings)
        guard hit.isEligible, let window = hit.window, let windowID = hit.windowID else {
            logIgnored(hit: hit, window: hit.window)
            return false
```

Correction proposée : Placer guard settings.enabled else { return false } avant le snapshot. Garder les moniteurs si nécessaire pour le rechargement à chaud.

Vérification proposée : Injecter un provider compteur. Appeler handleRightMouseDown avec enabled=false et vérifier zéro appel windows/displays et zéro écriture de store.

Effort : S. Risque de régression : LOW.

Mesure et retour arrière : Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse. Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:170

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:224

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/roadied/main.swift:443

### REL-010 — MEDIUM — Le focus annonce un succès lorsque AXRaise échoue sans délai dépassé

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieAX/SystemSnapshotProvider.swift:1049

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

focus renvoie l’inverse de noteResult pour AXRaise. Or noteResult renvoie vrai uniquement pour cannotComplete. Les erreurs failure, invalidUIElement et actionUnsupported deviennent donc un succès. L’erreur de modification AXFocusedWindow est également ignorée hors cannotComplete.

Scénario : La fenêtre est résolue, puis disparaît avant AXRaise, ou son application refuse l’action avec actionUnsupported. AXRaise renvoie cette erreur ; focus retourne néanmoins true.

Conséquence : Les appelants croient avoir activé la cible alors que l’action a échoué. Ils ne peuvent pas déclencher le repli ou signaler correctement l’échec.

Preuve :

```
        guard !registry.isQuarantined(pid) else { return false }
        let app = AXMessaging.application(pid)
        if registry.noteResult(AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element), pid: pid) {
            return false
        }
        return !registry.noteResult(AXUIElementPerformAction(element, kAXRaiseAction as CFString), pid: pid)
    }
```

Correction proposée : Enregistrer chaque AXError dans la quarantaine, mais comparer séparément le résultat final avec .success. Garder un repli seulement s’il est confirmé par une lecture du focus.

Vérification proposée : Injecter une action AX retournant success, failure, invalidUIElement, actionUnsupported et cannotComplete ; seul le succès confirmé doit donner true.

Effort : S. Risque de régression : MEDIUM.

Proposition de code, non appliquée :

```swift
let error = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
registry.noteResult(error, pid: pid)
return error == .success
```

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieAX/SystemSnapshotProvider.swift:295

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieAXTests/AXUnresponsiveAppsTests.swift:30

### REL-011 — MEDIUM — Les mauvais types numériques peuvent passer la validation puis devenir des défauts

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1702

Statut : confirmé par lecture et sonde isolée sur le code compilé. Correction : non appliquée.

decodeFlexibleDouble ignore les erreurs de décodage et renvoie nil, que les appelants remplacent par une valeur par défaut. Le rattrapage scalarTypeChecks ne reconnaît que les valeurs commençant par un guillemet double. Un booléen ou une chaîne TOML entre apostrophes n'est donc pas rejeté pour ces paramètres.

Scénario : Créer une configuration contenant [tiling] puis gaps_inner = true, ou gaps_inner = '30'. RoadieConfigLoader.validate ne produit aucune erreur pour cette clé ; RoadieConfigLoader.load remplace cette valeur par 4. Le test existant ne vérifie que gaps_inner = "not-a-number".

Conséquence : Une configuration incorrecte est annoncée valide. Une faute peut modifier la disposition au lieu de conserver la dernière configuration valide promise dans la documentation.

Preuve :

```
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
```

Correction proposée : Distinguer une clé absente d'une erreur de type. Accepter Int/Double uniquement, puis propager DecodingError pour les autres types. Retirer ensuite le rattrapage textuel devenu inutile et utiliser le parseur TOML pour produire le diagnostic.

Vérification proposée : Tester true, false, chaîne entre apostrophes, chaîne entre guillemets, tableau, clé absente, entier et nombre décimal. Les mauvais types doivent échouer pour load et validate ; l'absence doit garder le défaut.

Effort : S. Risque de régression : MEDIUM.

Preuve exécutée : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/probe-results.log

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1524

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/ConfigTests.swift:425

### REL-012 — MEDIUM — Le clic part même si la fenêtre cible ne peut plus être focalisée

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AppTargetQueryService.swift:706

Statut : confirmé par lecture du code. Correction : non appliquée.

TargetHintService ignore le résultat du focus de la fenêtre. LiveAppTargetProvider.waitUntilFocused revient sans résultat si la fenêtre a disparu, ou à expiration de son délai. click poste ensuite le clic aux anciennes coordonnées et annonce changed=true. La cible de recherche est un instantané qui peut rester ouvert 60 secondes.

Scénario : Ouvrir la recherche sur une fenêtre A et saisir le nom d'un de ses boutons. Fermer A avec la souris pendant que l'overlay reste ouvert, puis valider le résultat mémorisé. focus(windowID:) renvoie changed=false et waitUntilFocused ne trouve plus la fenêtre. Le code poste néanmoins le clic à la position mémorisée, désormais occupée par une autre fenêtre.

Conséquence : Un clic peut atteindre une autre application. L'échec de focus est masqué par un résultat de succès.

Preuve :

```
        guard let frame = (target.clickFrame ?? target.frame)?.cgRect else {
            return TargetActionResult(changed: false, message: "app click: no frame", target: target, error: "no_frame")
        }
        if let windowID = target.scope.windowId, let pid = AppTargetQueryService.pid(of: target) {
            waitUntilFocused(windowID: windowID, pid: pid, timeout: 0.5)
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        switch action {
        case .click:
            postClick(at: point, button: .left, down: .leftMouseDown, up: .leftMouseUp, clickCount: 1)
```

Correction proposée : Faire renvoyer un résultat explicite à la vérification de focus et abandonner si la fenêtre a disparu ou ne devient pas active. Revalider les coordonnées de la cible avant de poster les événements. Propager focus_failed ou stale_target.

Vérification proposée : Injecter un écrivain de focus qui échoue et un émetteur CGEvent espion. Vérifier zéro événement souris et changed=false. Couvrir fenêtre disparue, délai dépassé et cible déplacée.

Effort : S. Risque de régression : MEDIUM.

### REL-013 — MEDIUM — La réponse stages ne précise pas l’écran de chaque stage

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/AutomationSnapshotService.swift:101

Statut : confirmé par lecture; pas de reproduction macOS exécutée. Correction : non appliquée.

Les stages sont aplaties depuis les écrans et desktops. La sortie transporte seulement id et desktopId, alors que ces deux valeurs sont réutilisées sur différents écrans. AutomationStageSnapshot ne possède aucun displayId (Sources/RoadieCore/AutomationSnapshot.swift:75–97).

Scénario : Deux écrans possèdent chacun leur desktop 1/stage 1 vide. `query stages` retourne deux lignes de même id/desktopId, sans champ qui permette de les rattacher à leur écran. Un renommage ou mode différent ne résout pas l'identité.

Conséquence : Un client d'automatisation ne peut pas identifier sans ambiguïté une stage, notamment si elle est vide. Il ne peut pas associer fiablement un changement de stage au bon écran.

Preuve :

```
                                AutomationStageSnapshot(
                                    id: stage.id.rawValue,
                                    desktopId: String(desktop.id.rawValue),
                                    name: stage.name,
                                    mode: stage.mode.rawValue,
                                    windowIds: stage.windowIDs.map { String($0.rawValue) },
                                    focusedWindowId: stage.focusedWindowID.map { String($0.rawValue) }
                                )
```

Correction proposée : Ajouter displayId à AutomationStageSnapshot, le remplir depuis display.id dans stageSnapshots et adapter le contrat de décodage. Inclure également desktopId/displayId dans AutomationGroupSnapshot pour les mêmes références composites.

Vérification proposée : Construire deux écrans avec chacun desktop 1/stage 1 et des noms distincts. Vérifier que les réponses stages permettent de reconstituer le StageScope complet de chaque ligne.

Effort : S. Risque de régression : LOW.

### REL-014 — MEDIUM — config reload annonce une application sans changer la configuration du daemon

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:502

Statut : confirmé par lecture et sonde isolée. Correction : non appliquée.

La commande recharge une nouvelle instance de ConfigReloadService puis la détruit. Elle est aussi absente des commandes routées au daemon. Le service partagé utilisé par les composants garde son chemin actif. Le rechargement automatique du fichier habituel ne rend pas opérant un fichier alternatif passé à cette commande.

Scénario : Créer un fichier TOML alternatif avec gaps_inner=31 puis appeler config reload --config avec ce chemin. La réponse est status=applied et exitCode=0, mais ConfigReloadService.shared.state.activePath reste inchangé. Sonde exécutée sans joindre le daemon.

Conséquence : Le résultat positif ne correspond pas à une modification de la configuration utilisée. Les scripts et le diagnostic de configuration peuvent être trompés.

Preuve :

```
            } else if verb == "reload" {
                let result = ConfigReloadService().reload(path: configPath ?? RoadieConfigLoader.defaultConfigPath())
                if args.contains("--json") {
                    try printCodableJSON(result)
                } else {
                    out("status=\(result.status.rawValue)")
                    if let error = result.error {
                        out("error=\(error)")
                    }
```

Correction proposée : Router config reload vers le daemon et y appeler une instance partagée injectée. Conserver cette instance pour les composants. Tester le fichier alternatif et le maintien de la version précédente en cas de validation refusée.

Vérification proposée : Faire exécuter config reload via un routeur injecté. Vérifier son activePath et la valeur effective au prochain tick; vérifier qu’un fichier invalide garde la version réellement précédente.

Effort : M. Risque de régression : MEDIUM.

Preuve exécutée : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/probe-results.log

### REL-015 — MEDIUM — Le PID informatif ne prouve pas que le verrou du daemon est libre

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CommandSocketServer.swift:239

Statut : confirmé par lecture. Correction : non appliquée.

Le client assimile un fichier PID absent ou illisible à une absence du daemon. Pourtant ComponentLockFile possède le verrou avant d’écrire le PID, et scripts/start supprime ce PID même si le processus vivant ne correspond pas au binaire de développement. Le client peut alors exécuter une commande localement alors que le daemon possède encore le verrou et son socket.

Scénario : Démarrer un daemon autonome depuis Roadie.app, puis utiliser scripts/start : le test du chemin repo/bin/roadied ne reconnaît pas le daemon autonome, mais rm -f supprime roadied.pid. Une commande focus ou stage suivante passe alors dans local() malgré le daemon toujours vivant. Le même état existe brièvement entre flock et l’écriture du PID.

Conséquence : Le principe du seul exécutant des actions n’est plus garanti. La CLI peut utiliser une identité Accessibility différente et des registres de géométrie distincts pendant que le daemon continue ses actions.

Preuve :

```
    public static func isDaemonLockHeld(path: String = defaultLockPath) -> Bool {
        let pidPath = (path as NSString).deletingPathExtension + ".pid"
        guard let raw = try? String(contentsOfFile: pidPath, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return ProcessLiveness.isAlive(pid)
    }
```

Correction proposée : Essayer le socket avant le repli et établir réellement l’exclusion interprocessus pour toute la durée de l’exécution locale. Coordonner cette réservation avec un démarrage qui attend un client local au lieu d’échouer. Conserver le PID en cas de processus vivant non reconnu dans les scripts.

Vérification proposée : Test isolé : prendre le vrai verrou sans publier de PID, puis appeler execute avec un callback local espion. Exiger zéro exécution locale. Couvrir aussi une instance Roadie.app autonome et le démarrage simultané de la CLI.

Effort : M. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CommandSocketServer.swift:219

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/ComponentLockFile.swift:64

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/start:43

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/CLICommandRouterTests.swift:249

### REL-016 — MEDIUM — Déplacer une fenêtre vers son bureau actuel la masque

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DesktopCommands.swift:163

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

assignActiveWindow ne traite pas le cas où le bureau cible est déjà celui de la fenêtre. Il envoie toujours une frame de masquage quand follow est faux. Le masquage prime sur le placement calculé du même scope.

Scénario : Une fenêtre active appartient au bureau Roadie 1. Lancer roadie window desktop 1 sans --follow. La fonction construit une commande HiddenWindowPlacement pour cette même fenêtre.

Conséquence : La fenêtre est déplacée hors de sa zone visible alors que son bureau reste actif. La récupération ultérieure par le maintien de disposition n’a pas été vérifiée.

Preuve :

```
        // Plan unique (A15, T212) : fenêtre masquée et scope d'origine disposé en une écriture groupée.
        let (_, result) = service.applyCommandPlacement(
            CommandPlacement(
                hiding: [active.window.id: HiddenWindowPlacement.frame(for: active.window.frame.cgRect, on: display, among: snapshot.displays)],
                layoutScopes: Set([sourceScope, targetStageScope].compactMap { $0 })
            ),
            cause: "desktop.assign_window",
            generation: generation,
            events: events
        )
```

Correction proposée : Retourner sans écriture si la fenêtre appartient déjà au bureau demandé, comme le fait assign(windowID:to:displayID:). Choisir le masquage selon la visibilité réelle du scope cible.

Vérification proposée : Fixture avec une fenêtre sur le bureau actif : assignActiveWindow vers ce bureau doit laisser frames, ordre et groupes inchangés.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DesktopCommands.swift:206

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutCommandService.swift:369

### REL-017 — MEDIUM — La reconnexion d’un écran fusionne les stages de bureaux différents

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DisplayParkingService.swift:232

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

Le regroupement des stages garés utilise seulement logicalDisplayID. Le bureau du premier stage devient ensuite l’unique targetScope pour tous les stages du groupe. Chaque stage porte pourtant son propre origin.desktopID.

Scénario : Sur un écran externe, créer un stage avec une fenêtre sur le bureau Roadie 1 et un autre sur le bureau 2. Débrancher puis rebrancher l’écran avant matérialisation des stages garés. restoreParkedStages les range tous deux dans le bureau du premier origin.

Conséquence : Les stages du second bureau changent de bureau après reconnexion ; les identifiants identiques peuvent aussi être renommés avec un suffixe restored.

Preuve :

```
        let grouped = Dictionary(grouping: parkedStages) { stage in
            stage.origin!.logicalDisplayID
        }

        for (logicalDisplayID, stages) in grouped {
            guard let origin = stages.compactMap(\.origin).first else { continue }
            let fingerprint = fingerprintForRestore(
```

Correction proposée : Regrouper par identité logique de l’écran et bureau d’origine, ou restaurer séparément chaque sous-groupe desktopID. Ne retirer que les stages effectivement restaurés.

Vérification proposée : Ajouter un test aller-retour de parking avec deux desktopID pour le même logicalDisplayID et vérifier toutes les associations initiales.

Effort : M. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DisplayParkingService.swift:264

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DisplayParkingService.swift:282

### REL-018 — MEDIUM — L’abonnement perd des événements lors du remplacement du journal

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/EventSubscriptionService.swift:74

Statut : confirmé par lecture. Correction : non appliquée.

Le curseur ne mémorise que le nombre d’octets lus. Une rotation est détectée seulement si le nouveau fichier est plus court. Le service ne termine jamais la lecture de l’ancien fichier renommé et peut reprendre au milieu d’un nouveau fichier de taille égale ou supérieure.

Scénario : Lire A et conserver le curseur. Ajouter B, puis faire tourner le journal avant la lecture suivante en ajoutant C. B reste dans events.jsonl.1, que le service ne consulte pas. Si le nouveau fichier atteint déjà la taille du curseur, C peut également être sauté ou décodé depuis le milieu d’une ligne.

Conséquence : Le flux events subscribe manque silencieusement des notifications. Le consommateur ne peut plus reconstruire l’état par la seule succession des événements.

Preuve :

```
        defer { try? handle.close() }
        do {
            // Fichier plus court que le curseur : il a tourné (rotation), on relit depuis 0.
            let size = try handle.seekToEnd()
            let offset = size < cursor.offset ? 0 : cursor.offset
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
```

Correction proposée : Associer le curseur à l’identité du fichier (device/inode) et conserver le descripteur jusqu’à épuisement de l’ancienne génération. Reprendre ensuite le nouveau fichier depuis zéro. Si la rétention a déjà supprimé une génération, publier explicitement une rupture du flux.

Vérification proposée : Tester une rotation avec une dernière ligne non encore lue, puis des fichiers de remplacement plus courts, de même taille et plus longs. Vérifier chaque identifiant attendu exactement une fois. Le test existant ne couvre que le fichier plus court après consommation complète.

Effort : M. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/EventSubscriptionService.swift:18

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/EventLog.swift:265

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/StatePersistenceTests.swift:388

### REL-019 — MEDIUM — Le focus souris sélectionne une fenêtre cachée derrière une autre

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/FocusFollowsMouseController.swift:249

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

Le sélecteur filtre les fenêtres gérées puis choisit la plus petite surface. Il ne respecte pas leur ordre avant/arrière et ne vérifie pas isOnScreen. Le démarrage du glisser utilise la même logique de sélection par surface, après filtrage sur une bande de titre.

Scénario : Activer focus_follows_mouse. En mode float, placer une grande fenêtre au premier plan par-dessus une petite fenêtre de la même stage. Déplacer le curseur de plus de 2 points dans la zone commune : la petite fenêtre est sélectionnée et focalisée, alors que la grande est visible. Pour le glisser, placer la bande de titre de la petite sous le contenu de la grande : un glisser dans ce contenu peut être interprété comme un glisser de la fenêtre masquée.

Conséquence : Le focus et les gestes peuvent agir sur une fenêtre différente de celle montrée à l’utilisateur.

Preuve :

```
        snapshot.windows
            .filter { entry in
                guard let scope = entry.scope else { return false }
                return entry.window.isTileCandidate
                    && snapshot.state.activeScope(on: scope.displayID) == scope
                    && entry.window.frame.cgRect.contains(point)
            }
            .min { lhs, rhs in
                lhs.window.frame.width * lhs.window.frame.height < rhs.window.frame.width * rhs.window.frame.height
            }
```

Correction proposée : Identifier d’abord la première fenêtre visible contenant le point dans l’ordre CoreGraphics. Puis vérifier son éligibilité. Une fenêtre non gérée ou un panneau situé devant doit bloquer la recherche des fenêtres derrière.

Vérification proposée : Ajouter des snapshots avec grande fenêtre devant petite, panneau non géré devant, fenêtre isOnScreen=false et bande de titre masquée.

Effort : S. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DropPreviewController.swift:611

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TitlebarContextMenuController.swift:316

### REL-020 — MEDIUM — Un écran placé à gauche est confondu avec une ancienne zone de masquage

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/HiddenWindowPlacement.swift:34

Statut : confirmé par lecture et sonde isolée sur le code compilé. Correction : non appliquée.

Le prédicat classe toute fenêtre dont maxX < -1000 comme cachée. Il ne compare pas cette branche à la géométrie des écrans présents. Les observateurs de snapshots et les bordures emploient ce prédicat.

Scénario : Placer un écran de 3840 points à gauche du principal (x=-3840). Une fenêtre entièrement visible avec x=-3000 et width=1000 a maxX=-2000. Le prédicat renvoie true alors que l'écran contient la fenêtre.

Conséquence : La bordure de focus est masquée (/Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/BorderController.swift:44). Les déplacements de cette fenêtre n'actualisent plus ses cadres persistés, ni ceux du pin/signets (/Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:470–500). Une restauration peut donc utiliser un cadre ancien.

Preuve :

```
    /// `isHidden` plus l'ancienne position de masquage très loin à gauche (versions précédentes).
    /// Test unique pour tous les appelants qui filtrent les fenêtres réellement visibles.
    static func isHiddenOrLegacyOffscreen(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        frame.maxX < -1000 || frame.minX < -10000 || isHidden(frame, in: displays)
    }
```

Correction proposée : N'appliquer les coordonnées historiques qu'aux cadres hors des écrans actuellement présents. Garder le test des positions de parking actuelles.

Vérification proposée : Ajouter un cas écran secondaire x=-3840 et fenêtre x=-3000,width=1000. Vérifier prédicat false, bordure permise et mise à jour du membre/signets après déplacement.

Effort : S. Risque de régression : LOW.

Preuve exécutée : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/probe-results.log

Proposition de code, non appliquée :

```swift
static func isHiddenOrLegacyOffscreen(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
    if isHidden(frame, in: displays) { return true }
    let legacyPosition = frame.maxX < -1000 || frame.minX < -10000
    let intersectsDisplay = displays.contains { $0.frame.cgRect.intersects(frame) }
    return legacyPosition && !intersectsDisplay
}
```

### REL-021 — MEDIUM — Une mutation renvoie un succès métier après échec de persistance

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/JSONPersistence.swift:95

Statut : confirmé par lecture et sonde isolée sur le code compilé. Correction : non appliquée.

La transaction conserve correctement le fichier existant, mais avale les erreurs de verrouillage et d’écriture. Elle retourne tout de même la valeur calculée par le bloc métier. RailRuntimeStateStore.setPinned renvoie ainsi isPinned=true, et la commande rail pin affiche ce résultat avec un code 0, même si aucune nouvelle valeur n’a été persistée. Le cas du fichier corrompu exécute aussi le bloc sur une valeur de repli.

Scénario : Dans un environnement de test isolé, rendre rail.json illisible ou invalide puis appeler rail pin. Le bloc setPinned produit true, JSONPersistence refuse l’écriture, et CLICommandRouter termine avec 0. Une lecture suivante retrouve l’état précédent ou la valeur par défaut.

Conséquence : Un script appelant prend une mutation perdue pour une réussite. Pour les commandes routées, le message fputs reste en plus dans stderr du daemon, et non dans la réponse CLI.

Preuve :

```
        var value = original ?? defaultValue
        let output = try body(&value)
        guard original != value else { return output }
        do {
            try writeLocked(value, to: url, existing: nil)
            publish(value, at: url, signature: FileSignature(path: url.path))
        } catch {
            fputs("roadie: failed to persist \(label): \(error)\n", stderr)
        }
        return output
```

Correction proposée : Rentrer explicitement le résultat de persistance dans le contrat de mutate, ou propager les erreurs. Faire dépendre le code de sortie CLI de ce résultat et conserver la protection contre l’écrasement des fichiers corrompus.

Vérification proposée : Injecter une erreur de verrou, une erreur d’écriture et un fichier corrompu. Vérifier à chaque fois le code de sortie non nul et une erreur dans la réponse CLI. Vérifier que le fichier original est inchangé.

Effort : M. Risque de régression : MEDIUM.

Preuve exécutée : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/probe-results.log

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/JSONPersistence.swift:76

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailRuntimeState.swift:54

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CLICommandRouter.swift:545

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/StatePersistenceTests.swift:243

### REL-022 — MEDIUM — Le dépôt entre deux rails échoue si leurs stages portent le même identifiant

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailController.swift:776

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

Le contrôle de non-déplacement compare seulement les identifiants de stage. Ces identifiants sont locaux au couple écran/desktop. La destination a déjà été résolue sur le bon écran, mais la garde arrête la commande avant son exécution.

Scénario : Sur deux écrans, garder une stage 1 contenant une fenêtre sur chaque écran. Faire glisser une vignette du rail de la stage 1 du premier écran sur la carte stage 1 du second. target.stageID et drag.sourceStageID valent tous deux 1 : aucun déplacement ne part.

Conséquence : Un transfert courant entre écrans est ignoré sans message. Les tests de DropPreviewEngine entre écrans contournent ce chemin du rail.

Preuve :

```
        guard target.stageID != drag.sourceStageID else { return }
        print("rail drag window \(drag.windowID.rawValue) -> stage \(target.stageID.rawValue) index \(target.insertionIndex)")
        fflush(stdout)
        perform(.moveWindow(drag.windowID, target.stageID, target.insertionIndex, false), displayID: targetDisplayID)
        rebuildPanels()
```

Correction proposée : Comparer au minimum le couple écran/stage. Conserver le contexte desktop de départ si un changement de desktop pendant le geste doit être accepté.

Vérification proposée : Tester le dépôt entre écrans avec identifiants égaux, avec identifiants différents, puis le dépôt sur la même stage du même écran.

Effort : S. Risque de régression : LOW.

Proposition de code, non appliquée :

```swift
guard targetDisplayID != drag.displayID || target.stageID != drag.sourceStageID else { return }
```

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/DropPreviewEngineTests.swift:54

### REL-023 — MEDIUM — Le déplacement --no-follow rend visible une stage inactive

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:586

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

Le déplacement préserve la stage active de l’écran cible quand followFocus est faux. Pourtant, toutes les fenêtres déplacées sont inscrites dans restoring avec une frame centrée visible. Le plan de disposition global ne traite que les stages actives et ne retire donc pas ces restaurations.

Scénario : Deux écrans : stage 1 active sur écran A; stage 9 active avec une fenêtre sur écran B. Lancer roadie stage move-to-display 2 --no-follow. La stage 1 reste inactive sur B, mais ses fenêtres reçoivent des frames au centre de B.

Conséquence : Des fenêtres d’une stage inactive apparaissent sur le contexte courant et peuvent recouvrir les fenêtres de la stage active.

Preuve :

```
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        // Plan unique (A15, T212) : membres transférés et disposition des deux écrans en une écriture.
        var placement = CommandPlacement(layoutScopes: nil)
        for member in movingStage.members where windowsByID[member.windowID] != nil {
            placement.restoring[member.windowID] = centeredFrame(member.frame.cgRect, in: targetDisplay.visibleFrame.cgRect)
        }
        var failed = movingStage.members.count - placement.restoring.count
        service.removeLayoutIntent(scope: StageScope(displayID: sourceDisplay.id, desktopID: move.sourceDesktopID, stageID: requestedStageID))
        service.removeLayoutIntent(scope: targetScopeID)
        let result = service.applyCommandPlacement(placement, cause: "stage.move_display", generation: generation, events: events).result
```

Correction proposée : Quand la stage déplacée n’est pas activée, enregistrer ses frames de retour mais envoyer des frames de masquage. Ne restaurer immédiatement que la stage rendue active.

Vérification proposée : Étendre noFollowKeepsFocusDisplayAndTargetActiveStage : vérifier les frames finales des membres déplacés et leur invisibilité, puis les restaurer en activant la stage.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift:548

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:1191

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/StageDisplayMoveTests.swift:102

### REL-024 — MEDIUM — Le replay avale le relâchement de souris si la cible AX est absente

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetMacroService.swift:285

Statut : confirmé par lecture du code. Correction : non appliquée.

Pour un mouseUp portant une cible applicative, replay appelle activate(target.id), ignore son erreur et retourne immédiatement. Le mouseDown précédent a déjà été émis aux coordonnées. Aucun repli sur le mouseUp enregistré n'existe, contrairement à FR-031 et au scénario de la SPEC-009.

Scénario : Enregistrer un clic enrichi d'une cible AX avec include_ax_context=true. Relancer l'application, donc changer son PID dans app:<pid>/..., ou laisser app_targets.enabled=false lors du replay. Le down brut est émis, la résolution du vieux target.id échoue, puis le mouseUp est supprimé par return. Le résultat global annonce néanmoins replayed.

Conséquence : La séquence synthétique peut laisser un bouton appuyé sans relâchement correspondant. Le repli sur coordonnées promis n'est pas appliqué et l'utilisateur reçoit un faux succès.

Preuve :

```
    private func replay(_ event: TargetMacroEvent) {
        if let target = event.target,
           target.kind == .appElement,
           event.kind == .mouseUp {
            _ = TargetHintService(service: service).activate(target.id, action: .click)
            return
        }
        switch event.kind {
        case .mouseDown:
            guard let point = event.point?.cgPoint else { return }
            postMouse(type: .leftMouseDown, point: point)
```

Correction proposée : Traiter un geste complet de souris comme une unité : résolution de cible avant émission, puis clic sémantique réussi ou paire down/up aux coordonnées. Garantir le relâchement même si la résolution ou l'action échoue, et remonter l'erreur.

Vérification proposée : Rejouer via un émetteur espion une paire down/up dont la cible ne se résout pas. Vérifier qu'une paire complète est émise, que le bouton reste équilibré et qu'aucun deuxième down isolé n'apparaît.

Effort : S. Risque de régression : MEDIUM.

### REL-025 — MEDIUM — Les macros perdent le bouton droit et les modificateurs souris

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TargetMacroService.swift:439

Statut : confirmé par lecture du code. Correction : non appliquée.

Le capteur fusionne rightMouseDown/leftMouseDown et rightMouseUp/leftMouseUp dans les mêmes valeurs mouseDown/mouseUp. Le modèle ne conserve pas le bouton. Le lecteur rejoue toujours leftMouseDown/leftMouseUp et postMouse ne remet pas les modificateurs pourtant enregistrés.

Scénario : Activer record et replay, désactiver include_ax_context pour isoler le comportement brut. Enregistrer un clic droit sur un fichier, puis rejouer la macro. Elle produit un clic gauche. Enregistrer un Cmd-clic et relâcher Cmd avant replay : le lecteur souris ne transmet pas le drapeau enregistré.

Conséquence : Le lecteur exécute une action différente de celle enregistrée. Le menu contextuel attendu devient une sélection ou une ouverture.

Preuve :

```
    switch type {
    case .leftMouseDown, .rightMouseDown:
        let context = box.targetContext.context(for: point, includeAXContext: box.includeAXContext)
        box.append(TargetMacroEvent(t: elapsed, kind: .mouseDown, point: CGPointCodable(point), modifiers: modifiers, target: context.0, gridPath: context.1))
    case .leftMouseUp, .rightMouseUp:
        let context = box.targetContext.context(for: point, includeAXContext: box.includeAXContext)
        box.append(TargetMacroEvent(t: elapsed, kind: .mouseUp, point: CGPointCodable(point), modifiers: modifiers, target: context.0, gridPath: context.1))
```

Correction proposée : Conserver le bouton dans TargetMacroEvent avec une valeur par défaut compatible pour les anciens fichiers. Rejouer le type et les drapeaux enregistrés. Tester la séquence d'événements construite sans piloter le bureau.

Vérification proposée : Vérifier par émetteur espion un cycle droit down/up et un cycle gauche avec Commande ; comparer type, bouton et flags à l'entrée.

Effort : S. Risque de régression : MEDIUM.

### REL-026 — MEDIUM — La commande width sélectionne toujours le premier écran

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WidthAdjustmentService.swift:38

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

Le scope est choisi depuis snapshot.displays.first au lieu du scope de la fenêtre focalisée. La fenêtre réellement focalisée est sélectionnée ensuite, mais seulement dans la liste du premier écran.

Scénario : Deux écrans avec fenêtres en bsp. Focaliser une fenêtre sur le deuxième écran puis lancer roadie layout width ratio 0.67. L’ID focalisé ne figure pas dans entries du premier écran; la commande retourne no target window. Avec --all, elle redimensionne les fenêtres du premier écran.

Conséquence : La commande échoue sur les écrans secondaires ou applique --all sur un écran différent de celui choisi par l’utilisateur.

Preuve :

```
        guard let display = snapshot.displays.first,
              let scope = snapshot.state.activeScope(on: display.id),
              let stage = snapshot.state.stage(scope: scope)
        else {
            return WidthAdjustmentResult(changed: false, message: "width: unsupported layout")
        }
```

Correction proposée : Résoudre d’abord la fenêtre active, puis son scope et son écran. Partager la règle de sélection avec les autres commandes de disposition.

Vérification proposée : Ajouter une fixture à deux écrans, focus sur le second : seule la fenêtre du second doit changer sans --all; les fenêtres de ce même scope doivent changer avec --all.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieAX/SystemSnapshotProvider.swift:593

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WidthAdjustmentService.swift:57

### REL-027 — MEDIUM — Les ajustements relatifs utilisent la largeur de la première fenêtre

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WidthAdjustmentService.swift:57

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

currentRatio est calculé depuis entries.first avant la résolution de activeID. Quand la fenêtre focalisée n’est pas la première entrée, next, prev et nudge partent de la largeur d’une autre fenêtre.

Scénario : Fixture sur un écran de largeur 1000 : la première entrée mesure 300, la seconde mesure 600 et porte le focus. Appliquer nudge delta 0.05. Le calcul demande 350 pour la seconde fenêtre, au lieu de 650.

Conséquence : Un ordre qui demande d’agrandir peut rétrécir fortement la fenêtre active.

Preuve :

```
        let currentRatio = entries.first.map { $0.window.frame.width / display.visibleFrame.width } ?? 0.5
        let ratio = targetRatio(from: intent, current: currentRatio)
        let activeID = snapshot.focusedWindowID ?? stage.focusedWindowID ?? entries.first?.window.id
        let targets = intent.scope == .allWindows ? entries : entries.filter { $0.window.id == activeID }
        guard !targets.isEmpty else {
            return WidthAdjustmentResult(changed: false, message: "width: no target window")
```

Correction proposée : Calculer le ratio courant depuis l’entrée portant activeID. Définir explicitement la référence pour --all.

Vérification proposée : Ajouter deux fenêtres de largeurs différentes; focaliser celle qui n’est pas entries.first et vérifier les modes nudge, next et prev.

Effort : S. Risque de régression : LOW.

### REL-028 — MEDIUM — Focaliser une fenêtre temporairement absente efface son signet

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowBookmarkCommands.swift:52

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

L’absence de la fenêtre dans un seul snapshot entraîne removeBookmark immédiatement. Le fournisseur système ne remonte que les fenêtres CG actuellement à l’écran. Une fenêtre minimisée ou sur un autre Space peut donc perdre son signet alors qu’elle existe encore. Le délai de grâce présent dans StageStore n’est pas consulté.

Scénario : Créer un signet work pour une fenêtre, minimiser celle-ci, puis lancer roadie bookmark focus work. La fenêtre est absente du snapshot on-screen; la commande supprime le signet immédiatement.

Conséquence : Perte d’un raccourci utilisateur à cause d’une absence temporaire. La fonction renvoie changed=true pour cette suppression.

Preuve :

```
        guard let targetEntry = snapshot.windows.first(where: { $0.window.id == bookmark.windowID }) else {
            let removed = store.mutate { $0.removeBookmark(named: name) }
            if let removed {
                events.append(RoadieEvent(
                    type: "window.bookmark_pruned",
                    scope: removed.scope,
                    details: eventDetails(removed).merging(["reason": "focus_stale"], uniquingKeysWith: { lhs, _ in lhs })
                ))
            }
            return WindowCommandResult(message: "bookmark focus \(name): stale bookmark removed", changed: true)
```

Correction proposée : Conserver le signet pendant le délai de grâce. Tenter de rappeler la fenêtre de l’application via ses informations persistées. Réserver la suppression à une fermeture confirmée ou à la purge différée.

Vérification proposée : Provider sans la fenêtre pendant un seul snapshot : focus(work) ne doit pas supprimer le signet. Tester ensuite la réapparition et l’expiration de la grâce.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageStore.swift:455

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieAX/SystemSnapshotProvider.swift:610

### REL-029 — MEDIUM — Enregistrer une affinité supprime les autres actions des règles générées

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowRuleAffinityService.swift:178

Statut : confirmé par lecture du flux complet ; scénario non exécuté sur les fenêtres réelles. Correction : non appliquée.

saveAffinity et removeAppAffinity chargent puis réécrivent toutes les règles du fichier generated. render ne sérialise que les affectations et follow. Les actions manage, exclude, floating, layout, gap_override, scratchpad et emit_event des autres règles disparaissent.

Scénario : Dans le fichier generated, conserver une règle id="manual-rule" avec match.app="App A" et action.exclude=true. Ajouter une affinité pour App B par le menu. La règle manual-rule est encore présente, mais son action exclude a disparu après sauvegarde.

Conséquence : Perte de configuration sans erreur. Le commentaire du fichier promet seulement l’écrasement des règles affinity-* correspondantes, alors que les autres règles sont aussi altérées.

Preuve :

```
            lines.append("")
            lines.append("[rules.action]")
            append("assign_desktop", rule.action.assignDesktop, to: &lines)
            append("assign_display", rule.action.assignDisplay, to: &lines)
            append("assign_stage", rule.action.assignStage, to: &lines)
            if let follow = rule.action.follow {
                lines.append("follow = \(follow ? "true" : "false")")
            }
            lines.append("")
```

Correction proposée : Préserver les règles non modifiées ou sérialiser tous les champs du modèle RuleAction avec un encodeur TOML. Vérifier un aller-retour exact avant écriture atomique.

Vérification proposée : Précharger une règle non-affinity avec toutes les actions, enregistrer puis retirer une autre affinité et comparer la règle initiale après décodage.

Effort : S. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowRuleAffinityService.swift:42

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowRuleAffinityService.swift:72

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowRuleAffinityService.swift:155

### REL-030 — MEDIUM — La configuration master_ratio n'arrive jamais au moteur de disposition

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/LayoutTypes.swift:74

Statut : confirmé par recherche de tous les usages. Correction : non appliquée.

TilingConfig décode master_ratio et le validateur l'accepte. LayoutRequest ne porte pas cette valeur. Le seul appel de production à MasterStackLayoutStrategy utilise toujours son initialiseur sans argument. Changer master_ratio n'a donc aucun effet sur le calcul.

Scénario : À fenêtres et frames identiques, remplacer master_ratio=0.6 par master_ratio=0.8 dans [tiling], puis recalculer une stage masterStack. Les deux configurations produisent la même requête de layout et donc le même plan. Sans frame observée utilisable, le ratio de repli reste 0.6.

Conséquence : Une option présentée dans les deux guides de configuration est silencieusement ignorée. L'utilisateur ne peut pas choisir la proportion initiale du panneau principal.

Preuve :

```
        case .bsp:
            return BSPLayoutStrategy().plan(request)
        case .masterStack:
            return MasterStackLayoutStrategy().plan(request)
        case .float:
            return FloatLayoutStrategy().plan(request)
```

Correction proposée : Ajouter le ratio à LayoutRequest, le transmettre depuis la configuration dans les producteurs de requêtes, puis appeler MasterStackLayoutStrategy(masterRatio: ...). Ajouter un test depuis une config TOML non standard jusqu'aux placements.

Vérification proposée : Avec container 1000×500, sans marges ni frames observées, vérifier qu'un ratio configuré à 0.8 donne 800 points au panneau principal, puis qu'un autre ratio modifie le résultat.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:176

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/MasterStackLayoutStrategy.swift:7

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:1564

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift:2656

### REL-031 — MEDIUM — Un espacement trop grand produit une fenêtre hors du conteneur

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieTiler/MasterStackLayoutStrategy.swift:38

Statut : confirmé par sonde isolée sur le moteur compilé. Correction : non appliquée.

Le moteur ramène la hauteur disponible à zéro, mais continue à ajouter la totalité des espacements. La dernière hauteur devient négative, puis CGRect.integral produit un rectangle hors du conteneur. Aucune borne supérieure de gap adaptée à ce conteneur n’est appliquée.

Scénario : LayoutRequest masterStack, conteneur 1000×500, trois fenêtres, innerGap=600. La sonde obtient pour la fenêtre 3 le cadre x=840,y=500,width=160,height=100. Le cadre dépasse la hauteur du conteneur.

Conséquence : Une configuration numérique valide peut proposer une fenêtre invisible en partie et une autre de hauteur nulle. Le résultat réel AX peut ensuite être refusé ou ajusté.

Preuve :

```
        let usableHeight = max(0, rect.height - gap * CGFloat(stack.count - 1))
        let baseHeight = floor(usableHeight / CGFloat(stack.count))
        var y = rect.minY
        for (index, windowID) in stack.enumerated() {
            let isLast = index == stack.count - 1
            let height = isLast ? rect.maxY - y : baseHeight
            placements[windowID] = CGRect(
                x: rect.minX + masterWidth + gap,
                y: y,
                width: stackWidth,
```

Correction proposée : Borner les espacements par les dimensions réellement disponibles et le nombre de séparations. Vérifier les dimensions finies et positives, puis refuser tout plan qui déborde. Ajouter des cas de conteneur petit et de marge excessive aux tests des stratégies.

Vérification proposée : Rejouer exactement la sonde avec gap=600 : aucune frame ne doit être vide ni dépasser 1000×500. Vérifier aussi zéro, marges normales, n=1 et config non finie.

Effort : S. Risque de régression : MEDIUM.

Preuve exécutée : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/probe-results.log

### REL-032 — MEDIUM — La désinstallation laisse une instance autonome active

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/uninstall:28

Statut : confirmé par lecture. Correction : non appliquée.

Le script arrête seulement le LaunchAgent s’il est chargé. Une instance démarrée en ouvrant Roadie.app ou depuis tmux n’est pas arrêtée. Le script supprime ensuite les binaires et propose la suppression des dossiers d’état alors que cette instance continue à les utiliser.

Scénario : Dans un environnement de validation isolé, ouvrir Roadie.app sans LaunchAgent chargé puis lancer la désinstallation. Le bloc launchctl prend la branche non chargé, mais les suppressions s’exécutent quand même. Le processus autonome reste vivant.

Conséquence : Roadie continue de gérer les fenêtres après désinstallation. La suppression facultative d’état peut intervenir pendant son utilisation, et les fichiers peuvent être recréés par l’instance restée active.

Preuve :

```
# 2. Arrêter et décharger le service (sans kill : launchd envoie le signal d'arrêt).
if launchctl print "$service" >/dev/null 2>&1; then
  launchctl bootout "$service"
  echo "$label arrêté"
else
  echo "$label n'était pas chargé"
fi

# 3. Supprimer le LaunchAgent et les binaires installés.
rm -f "$plist" "$local_bin_dir/roadied" "$local_bin_dir/roadie"
```

Correction proposée : Réutiliser la procédure de scripts/stop avant toute suppression. Vérifier que tous les composants concernés sont arrêtés. Refuser la suppression des binaires et de l’état si l’arrêt n’est pas confirmé.

Vérification proposée : Ajouter aux tests simulés de cycle de vie le cas Roadie.app autonome sans LaunchAgent et le cas d’un processus qui refuse de sortir. Aucune suppression ne doit suivre un échec d’arrêt.

Effort : M. Risque de régression : MEDIUM.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/stop:39

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/roadied/main.swift:541

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/tests/test_lifecycle.py:124

### TEST-001 — MEDIUM — Le test des requêtes vérifie seulement le nom recopié dans la réponse

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/QueryCommandTests.swift:36

Statut : confirmé par lecture; pas de reproduction macOS exécutée. Correction : non appliquée.

Ce test prépare un groupe réel, puis vérifie seulement .kind. AutomationQueryService.result recopie directement ce nom depuis l'entrée. Les cinq assertions resteraient vertes si toutes les données étaient .null ou des tableaux vides.

Scénario : Remplacer mentalement les cinq charges utiles par .null : les attentes .kind aux lignes 38–42 sont inchangées. Le groupe 'pair' préparé aux lignes 32–35 n'est jamais vérifié dans le résultat.

Conséquence : Le test annonce couvrir cinq charges utiles sans détecter leur absence, leur mauvais contenu ou leur mauvaise association écran/desktop.

Preuve :

```
        let query = AutomationQueryService(service: snapshotService, configPath: try fixturePath())

        #expect(query.query("displays").kind == "displays")
        #expect(query.query("desktops").kind == "desktops")
        #expect(query.query("stages").kind == "stages")
        #expect(query.query("groups").kind == "groups")
        #expect(query.query("rules").kind == "rules")
```

Correction proposée : Décoder les charges utiles et vérifier au minimum les IDs attendus, les deux membres du groupe, sa stage et les règles chargées. Garder une assertion séparée pour le nom de réponse.

Vérification proposée : Introduire une mutation locale dans une copie d'audit qui remplace groups.data par .null : le test renforcé doit échouer.

Effort : S. Risque de régression : LOW.

### TEST-002 — MEDIUM — Les tests de cibles ne couvrent pas le raccordement aux effets système

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/TargetModeRuntimeControllerTests.swift:18

Statut : confirmé par lecture du code. Correction : non appliquée.

Les huit fichiers de tests cibles vérifient le modèle, les conversions, la géométrie et des fournisseurs simulés. TargetModeRuntimeControllerTests teste les notifications et GridFocusPicker, sans lancer le contrôleur. Les tests AppTargetQueryService ne parcourent pas LiveAppTargetProvider.scanVisibleWindows ; TargetSearchHotkeyTests vérifie seulement la résolution pure, et TargetMacroServiceTests seulement le JSON et nearestTarget. Les erreurs d'activation, d'écran et de replay décrites ici ne peuvent donc pas être détectées par ces suites.

Scénario : Les tests actuels restent inchangés alors que la fermeture activate résout une autre liste, que frozenRoot ignore displayIndex ou que le replay supprime mouseUp. Les tests de ces trois raccordements sont absents.

Conséquence : La couverture fonctionnelle annoncée ne permet pas de conclure sur Carbon, CGEvent, le focus réel ou la livraison concurrente des fenêtres. Le nombre total de tests peut masquer ces trous.

Preuve :

```
        let parsed = try #require(TargetModeRuntimeCommand(userInfo: command.userInfo))

        #expect(parsed.name == "targets.interactive")
        #expect(parsed.string("source") == "all")
        #expect(parsed.bool("includeAppTargets"))
        #expect(parsed.double("duration") == 10)
```

Correction proposée : Ajouter des interfaces minimales injectables pour la présentation, le focus, l'émission d'événements et l'enregistrement du raccourci. Tester les interactions aux frontières et les annulations, sans écrire de tests qui recopient le calcul interne.

Vérification proposée : Les régressions REL-201 à REL-205 doivent faire échouer au moins un test comportemental. Un scénario manuel séparé sur macOS valide Carbon et CGEvent sans confondre ce contrôle avec des tests unitaires.

Effort : M. Risque de régression : MEDIUM.

### TEST-003 — MEDIUM — Le test des commandes de groupe ne contrôle que changed

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/WindowGroupCommandTests.swift:15

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

Le test exécute create, add, focus, remove et dissolve mais ne relit aucun membre ni activeWindowID. Un ajout ou une focalisation incorrecte peut passer tant que la commande renvoie changed=true; la dissolution finale ne vérifie pas les étapes intermédiaires.

Scénario : Mutation conceptuelle : supprimer group.add ou group.focus tout en conservant la création du groupe et les valeurs de retour. Les attentes montrées restent satisfaites.

Conséquence : Le test donne peu de protection sur le comportement métier du seul pipeline complet de commandes de groupe.

Preuve :

```
        #expect(groups.create(id: "terminals", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)]).changed)
        #expect(groups.add(windowID: WindowID(rawValue: 3), to: "terminals").changed)
        #expect(groups.focus(windowID: WindowID(rawValue: 3), in: "terminals").changed)
        #expect(groups.remove(windowID: WindowID(rawValue: 2), from: "terminals").changed)
        #expect(groups.dissolve(id: "terminals").changed)
```

Correction proposée : Après chaque commande, vérifier la liste exacte des membres, le membre actif et la disparition finale. Ajouter un identifiant absent et une création invalide.

Vérification proposée : Une mutation de add, focus ou remove doit faire échouer une attente sur le contenu de l’état, même si changed reste vrai.

Effort : S. Risque de régression : LOW.

### TEST-004 — MEDIUM — Le test de l’indicateur de groupe ne couvre aucun rendu réellement utilisé

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/WindowGroupIndicatorTests.swift:20

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

Le test crée un snapshot sans fenêtre et vérifie seulement la chaîne produite par groupIndicator. La recherche des appels ne trouve aucun appel en production. BorderController.refresh transmet uniquement frame, color, thickness et cornerRadius au panneau. La tâche T068 de la SPEC-002 est pourtant cochée comme indicateur visuel livré.

Scénario : Créer un groupe de deux fenêtres puis focaliser l’une d’elles. Le test reste vert même si groupIndicator n’est jamais relié à la vue. Le chemin de rendu actuel ne transmet aucun identifiant de groupe ni membre actif.

Conséquence : La présence du test ne protège pas l’exigence de retour visuel FR-012. Une fonction de présentation isolée donne une fausse impression de couverture de l’interface.

Preuve :

```
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay()],
            windows: [],
            state: state
        )

        let indicator = BorderController().groupIndicator(for: WindowID(rawValue: 1), snapshot: snapshot)

        #expect(indicator == "docs:2/2")
```

Correction proposée : Brancher un modèle visuel de groupe sur le panneau et tester le modèle effectivement transmis au rendu. Si cette fonction n’est plus dans le produit, corriger explicitement le statut de la SPEC-002.

Vérification proposée : Un test doit échouer quand on retire la transmission de l’état de groupe au panneau. Couvrir groupe présent, membre actif et dissolution.

Effort : M. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/BorderController.swift:51

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/specs/002-roadie-ecosystem-upgrade/tasks.md:157

### MIN-002 — LOW — Neuf surcharges répètent le même encodeur JSON

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DaemonSnapshot.swift:2075

Statut : confirmé par lecture; pas de reproduction macOS exécutée. Correction : non appliquée.

SnapshotEncoding répète neuf fois le même corps pour neuf types Encodable. Seul le type du paramètre change. Une fonction générique conserve les appels existants et centralise les options d'encodage.

Scénario : Modifier une option d'encodage : il faut synchroniser neuf corps identiques, de 2075 à 2136.

Conséquence : Charge de maintenance évitable, sans différence métier entre les surcharges.

Preuve :

```
    public static func json(_ snapshot: DaemonSnapshot, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(snapshot)
        return String(decoding: data, as: UTF8.self)
    }

    public static func json(_ plan: ApplyPlan, pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(plan)
        return String(decoding: data, as: UTF8.self)
```

Correction proposée : Remplacer les neuf surcharges par json<T: Encodable>(_ value: T, pretty: Bool = true).

Vérification proposée : Comparer les sorties JSON actuelles et génériques pour les neuf types, en modes compact et pretty.

Effort : S. Risque de régression : LOW.

Proposition de code, non appliquée :

```swift
public static func json<T: Encodable>(_ value: T, pretty: Bool = true) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}
```

### MIN-003 — LOW — Quatre contrôles de plage portent sur des valeurs déjà bornées

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1620

Statut : confirmé par suivi du décodage et de tous les appels privés. Correction : non appliquée.

La validation privée reçoit uniquement les objets décodés par les initialisateurs, qui bornent déjà les paramètres. Les contrôles de AppTargets.maxDepth et de TargetGrid.rows, columns, maxDepth ne peuvent jamais produire leur erreur. Ils donnent une impression de validation stricte alors que les valeurs sont corrigées silencieusement avant ce point.

Scénario : 28 lignes sans effet à maintenir. Les règles semblent exister deux fois alors qu'une seule est réellement appliquée.

Conséquence : 28 lignes sans effet à maintenir. Les règles semblent exister deux fois alors qu'une seule est réellement appliquée.

Preuve :

```
        if config.maxDepth < 1 || config.maxDepth > 40 {
            items.append(ConfigValidationItem(
                level: .error,
                path: "experimental.app_targets.max_depth",
                message: "must be between 1 and 40"
            ))
        }
```

Correction proposée : Conserver les bornes dans les initialisateurs et supprimer ces quatre branches mortes à comportement constant. Si le produit doit rejeter les valeurs hors plage, valider les données brutes avant leur normalisation, dans un changement fonctionnel distinct.

Vérification proposée : La suppression ne doit changer aucun rapport de validation sur les fichiers TOML. Vérifier notamment max_depth=99 et rows=1 avant et après.

Effort : XS. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:661

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:779

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1632

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1639

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieCore/Config.swift:1653

### MIN-004 — LOW — Deux pipelines presque identiques gèrent les déplacements de bureau

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DesktopCommands.swift:154

Statut : confirmé par lecture du code; scénario non exécuté. Correction : non appliquée.

assignActiveWindow et assign(windowID:to:displayID:) répètent la mutation des scopes, la suppression des intentions, le placement, l’événement et le résultat. Une divergence existe déjà : seul le second refuse le bureau courant.

Scénario : Pour modifier la politique de visibilité ou de retrait des pins, le mainteneur doit modifier deux blocs équivalents dans le même fichier.

Conséquence : Charge cognitive et risque de correction appliquée à une seule entrée. Estimation locale : environ 60 lignes suppressibles après extraction du corps partagé.

Preuve :

```
        if let sourceScope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: targetStageScope)

        if follow {
            return switchDisplay(display, to: desktopID, snapshot: snapshot, generation: generation)
        }
```

Correction proposée : Conserver les deux points d’entrée publics et extraire un helper privé recevant la fenêtre, le snapshot et le bureau cible. Conserver les différences de validation explicites aux entrées.

Vérification proposée : Les tests existants de transfert, de retrait de pin et de transaction doivent conserver leur résultat; ajouter les scénarios du bureau courant et de l’écran cible actif.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DesktopCommands.swift:230

### PERF-007 — LOW — Le lecteur de ligne réanalyse tout le préfixe à chaque paquet

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CommandSocketServer.swift:329

Statut : confirmé par lecture. Correction : non appliquée.

Le commentaire annonce O(n), mais firstIndex repart du début de data après chaque réception. Avec des fragments de taille fixe et le saut de ligne en fin de réponse, le travail cumulé est quadratique. Les requêtes sont bornées à 64 Kio, mais les réponses sont lues avec limit égal à Int.max.

Scénario : Une réponse JSON de grande taille arrive en nombreux fragments avant son unique saut de ligne final. Chaque fragment déclenche une nouvelle recherche sur tous les octets déjà reçus.

Conséquence : Le coût CPU de lecture augmente plus vite que la taille de la réponse. Aucun temps d’exécution n’a été mesuré pendant cet audit.

Preuve :

```
    /// Lit jusqu'au premier `\n` (exclu) ou la fin du flux. O(n), n = taille de la ligne.
    static func readLine(_ fd: Int32, limit: Int, deadline: Date) -> ReadResult {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let newline = data.firstIndex(of: 0x0A) {
                return newline - data.startIndex > limit ? .tooLarge : .line(data[data.startIndex..<newline])
            }
            guard data.count <= limit else { return .tooLarge }
            let count = recv(fd, &chunk, chunk.count, 0)
```

Correction proposée : Rechercher le saut de ligne seulement dans le nouveau fragment ou mémoriser le dernier index parcouru. Fixer également une limite de réponse conforme au contrat attendu.

Vérification proposée : Injecter la même ligne en fragments fixes pour plusieurs tailles et vérifier que chaque octet est parcouru au plus une fois, sans changer les règles de fin de flux et de taille maximale.

Effort : M. Risque de régression : MEDIUM.

Mesure et retour arrière : Comparer durée et allocations sur la même entrée, avant/après. Vérifier les résultats et leur ordre. Retirer le correctif ciblé si un comportement ou une mesure régresse. Complexité établie par lecture; aucune latence ni allocation mesurée sur le bureau réel.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/CommandSocketServer.swift:261

### QUAL-001 — LOW — Les guides décrivent des interactions qui ne correspondent plus au code

Fichier : /Users/moi/Nextcloud/10.Scripts/39.roadie/README.fr.md:528

Statut : confirmé par lecture; scénario UI non exécuté. Correction : non appliquée.

Les README français et anglais décrivent des chevrons de réorganisation absents du rendu actuel. RailController réalise cette action au glisser du bouton droit. Les guides de fonctions attribuent aussi le drag/drop au composant titlebar-menu, alors que son contrôleur appartient à RailController.

Scénario : Suivre README.fr.md pour réordonner une stage : chercher les chevrons annoncés. En exécution modulaire, suivre docs/fr/features.md pour lancer titlebar-menu seul en espérant obtenir le glisser-déposer : WindowDragReorderController n’est créé que par RailController.

Conséquence : La documentation oriente vers des commandes ou gestes inutilisables dans le composant décrit.

Preuve :

```
- Un clic dans une zone vide du rail ne fait rien par défaut, pour qu’un clic raté ne masque pas la stage active. Mets `empty_click_hide_active = true` seulement si tu veux qu’une zone vide bascule vers une stage vide.
- Drag une thumbnail vers une autre stage pour y déplacer la fenêtre.
- Drag une thumbnail vers la scène active pour la ramener.
- Drag une thumbnail vers une zone vide du rail pour la placer dans une stage vide ou nouvellement créée.
- Utiliser les chevrons au-dessus et au-dessous d’une stage pour réordonner les stages.
```

Correction proposée : Mettre à jour les versions FR/EN : décrire le glisser au bouton droit et attribuer le drag/drop au rail. Relire aussi la phrase aucun moteur de raccourcis dans les pages CLI pour mentionner l’exception search_hotkey.

Vérification proposée : Comparer la liste des interactions aux branches handleRightMouse et aux points de création des contrôleurs. Garder les pages FR/EN cohérentes.

Effort : S. Risque de régression : LOW.

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/README.md:540

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/docs/fr/features.md:40

Autre site : /Users/moi/Nextcloud/10.Scripts/39.roadie/docs/en/features.md:40

## Complexité algorithmique — Article XVIII

Contrôles effectués : boucles imbriquées, recherches linéaires dans les boucles, appels AX répétés, tris, concaténations, I/O, récursions et copies. Les parcours quadratiques/cubiques signalés ont des scénarios atteignables et un correctif ciblé. Le coût de réparation de voisinage est conditionnel à un refus de taille; il ne survient pas à chaque tick. Les usages de Set/Dictionary et le groupement par PID réduisent déjà plusieurs coûts. Aucun gain de latence chiffré n’est promis. Les annotations des fonctions publiques ont été examinées par chemins importants, sans inventaire automatisé exhaustif. Aucune base SQL ni API réseau par ligne n’existe dans ce périmètre.

## Minimalisme & Frugalité

**Potentiel minimalisme : ~300 lignes suppressibles à comportement constant.**

Estimation statique dédoublonnée : environ 28 lignes de validations inatteignables, 110 lignes de helpers/menus du rail, 60 lignes des pipelines de déplacement de bureau, 56 lignes des encodeurs JSON répétés et 45 lignes de nettoyage/émission d’événements de cibles. Total estimé : 299, arrondi à 300. Il ne s’agit pas d’un diff implémenté.

Checklist appliquée : helpers sans règle propre, états dérivés, wrappers, abstractions, défenses inutiles, dépendances et fonctions sans besoin prouvé. Les protocoles de layout ont quatre implémentations. Les abstractions AX servent les tests et les garde-fous. Les aliases persistés et les migrations assurent la compatibilité. Ils ne sont pas comptés comme suppressibles. Les heuristiques Electron/CEF ont des cas concrets et des tests. Aucun retrait de fonctionnalité n’est proposé sans besoin validé.

## Vertus LLM & Responsabilité Future

La séparation Core/AX/Stages/Tiler et les tests des invariants réduisent la charge future. La charge augmente toutefois dans les contrôleurs longs, les pipelines dupliqués et les résultats de succès qui ne représentent pas l’effet réel. Les tests des seuls flags changed, noms de requêtes et chaînes d’indicateurs laissent passer des défauts visibles.

Le volume des moteurs est en partie justifié par les contraintes macOS, le plein écran, les arrondis et les fenêtres qui refusent de changer de taille. Il n’est pas intégralement justifié : les suppressions estimées et les tests peu discriminants sont détaillés ci-dessus. Les abstractions signalées servent généralement des frontières réelles. Une suppression massive ne serait pas adaptée.

Les invariants sont expliqués dans les ADR et les tests. Les contre-exemples montrent où le mainteneur doit compléter le contrat. Aucun jugement sur l’origine IA du code, sur la compréhension d’un auteur ou sur une absence de relecture humaine n’est tiré du style. Aucune intégration LLM applicative n’a été trouvée. L’historique de génération n’a pas fait l’objet d’une preuve indépendante.

## Points positifs vérifiés

- Socket créé en 0600, taille de requête limitée et commandes à flux refusées.
- État JSON écrit atomiquement; mutations principales sous verrou; fichier corrompu conservé. La remontée du succès reste à corriger.
- Délais AX et quarantaine par PID. Écritures groupées par application.
- Horloge simulée dans les tests du scheduler; couverture de la coalescence et des suspensions.
- Tests de projection BSP, tailles minimales et limites d’arrondi.
- Bonne couverture des règles pures de recherche et des collisions CFEqual/CFHash.
- Reprise des fenêtres : appels AX hors verrou et revérification du propriétaire avant validation.

## Sécurité et dépendances

Aucune injection shell ni exposition réseau non autorisée confirmée dans les chemins lus. Les processus sont lancés avec arguments séparés aux sites examinés. La surface prioritaire est locale : le processus du même utilisateur, les arguments erronés et les actions système déjà autorisées à Roadie. Les protections de socket ne neutralisent pas un crash produit par une commande acceptée. Les titres de fenêtres et journaux ont été inclus dans les recherches de données sensibles. Aucun secret confirmé dans les sources et scripts analysés.

TOMLKit 0.6.0 est la seule dépendance SwiftPM directe, fixée par révision dans /Users/moi/Nextcloud/10.Scripts/39.roadie/Package.resolved. Aucun scan de vulnérabilités des dépendances n’a été effectué. Les cases OWASP web, paiement et LLM sont sans objet pour ce binaire local. Les contrôles de permissions, fichiers, processus et état persistent dans le périmètre. Aucun pourcentage JSCPD n’est annoncé : duplication étudiée manuellement.

## Tests, preuves et limites

Les commandes et leurs sorties restent dans /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation. Le code a été copié sous ce dossier avec les manifests, les fixtures et la dépendance déjà présente. Les caches et TMPDIR ont été redirigés dans ce même dossier. HOME n’a pas été modifié. Le répertoire de build du dépôt n’a pas servi de destination d’écriture.

Résultats :

- swift build : succès, 29,62 s selon SwiftPM.
- swift test : 880 tests sélectionnés, premier passage 879 succès + 1 échec dû à l’exemple absent de la copie. Reprise ciblée : 1 succès. Aucun échec produit restant.
- Test socket exclu : CLICommandRouterTests.socketRoundTripRunsRouterAndRefusesOthers. Son chemin court est codé en dur sous /tmp, hors périmètre d’écriture autorisé.
- Python measure-layout-reactivity : 7 tests réussis. Les tests Python de cycle de vie ne sont pas exécutés.
- Sondes compilées : mauvais type numérique accepté avec valeur par défaut; cadre hors écran avec gap excessif; écran gauche pris pour une zone cachée; succès de mutation malgré fichier corrompu; config reload sans changement du service partagé.

Journaux :

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/build-no-nested-sandbox.log

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/test.log

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/test-example-recheck.log

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/probe-results.log

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/test-measure.log

Non vérifié : interaction réelle avec Firefox/Electron/CEF; clics CGEvent; enregistrement et conflit Carbon; autorisations TCC; changements physiques d’écran; charge et mémoire; analyseurs de courses/mémoire; fuzzing; toutes les branches de tests; CVE des dépendances; exactitude de chaque ancienne spec. Les correctifs proposés sont non exécutés. La course de suppression tardive du socket reste plausible, écartée du scoring et conservée dans /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/deferred-and-merged.json.

## Traçabilité et conformité

Aucun code, test, document ou fichier de configuration du dépôt n’a été modifié. Aucune branche, aucun commit, aucun push. Aucun processus existant arrêté, tué ou relancé. Aucun make install/restart. Les fichiers générés sont uniquement sous /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01. Le pointeur /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/latest reste inchangé pour respecter cette contrainte.

Les identifiants de constats des sous-rapports pouvaient entrer en collision. Ils ont été renumérotés ici. source_artifact/source_id préservent leur origine dans le JSON. Les fingerprints sont calculés par le script canonique. Les propositions planGroup identiques ont été fusionnées. La baseline absente n’a pas été créée.

Artefacts principaux :

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/grade.json

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/cycle-1/aggregated-findings.json

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/counter-audit.json

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/counter-runtime-perf.json

/Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/read-inventory.json

Validation finale du protocole : 0 erreur, 0 avertissement. Journal : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/session-validator.log.

Intégrité : les 465 fichiers suivis présents dans le relevé initial gardent exactement leur empreinte SHA-256. HEAD reste acc10e1. Seul le dossier autorisé apparaît dans git status. Preuve : /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/integrity-check.json.

Les copies de travail, binaires et caches créés pour les tests ont été retirés après validation. Les logs, données de sonde et sources de sonde restent disponibles. Les commandes exactes sont conservées dans /Users/moi/Nextcloud/10.Scripts/39.roadie/audits/2026-10-13/full-codebase-01/validation/commands.json. Le nettoyage ne touche aucun fichier préexistant du dépôt.
