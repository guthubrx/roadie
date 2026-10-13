# Contre-revue round 1 (GPT-6-Astra, Codex) - verdict REJECT

Périmètre : `main..226b9360` hors `audits/`. Build et 992 tests verts. 34 constats d'audit validés ;
16 constats de revue ci-dessous (R1-01 à R1-16). Chemins relatifs au worktree 022.

| ID | Sév. | Constat d'origine | Fichier | Problème | Correction attendue |
|----|------|-------------------|---------|----------|---------------------|
| R1-01 | HIGH | PERF-002 | `Sources/RoadieDaemon/DaemonSnapshot.swift:621`, `Sources/RoadieTiler/BSPTree.swift:61` | La réconciliation de l'arbre avant la stratégie appelle encore `tree.contains` pour chaque membre et lit plusieurs fois `windowIDs`, qui concatène récursivement (O(n²) sur un arbre en chaîne). | Collecter les feuilles une fois (accumulateur), ensemble pour l'appartenance ; `windowIDs` en O(n). |
| R1-02 | MED | REL-021 | `JSONPersistence.swift:130`, `StageStore.swift:189` | `StageStore` et `LayoutIntentStore` utilisent encore `mutate` : une commande de stage peut annoncer un changement, voire appliquer des déplacements AX, sans persistance. | Propager le résultat de persistance jusqu'aux commandes ; aucun effet système après une transaction refusée. |
| R1-03 | MED | REL-015 | `CommandSocketServer.swift:219` | Pas de PID + pas de socket ne prouve pas que le verrou est libre ; aucune réservation pendant `local()`. Daemon qui a pris le verrou sans PID/socket, ou qui démarre juste après les sondes. | Exclusion commune couvrant toute l'exécution locale, compatible avec le démarrage du daemon. |
| R1-04 | MED | REL-012 | `AppTargetQueryService.swift:733` | Après l'attente du focus, le cadre de clic vient du résultat conservé par l'overlay, sans vérifier que l'élément l'occupe encore (fenêtre déplacée, défilement, bouton disparu). | Revalider la cible et sa géométrie après le focus ; `stale_target` sinon. |
| R1-05 | MED | REL-014 | `LayoutMaintainer.swift:1811` | Le cache du moteur de règles est invalidé par `RoadieConfigLoader.rulesVersion()` sans chemin (fichier par défaut) : après `config reload` d'un autre fichier, les anciennes règles restent actives. | Invalider avec la configuration réellement active (chemin et règles). |
| R1-06 | MED | REL-025 | `TargetMacroService.swift:351` | Le chemin sémantique réduit le geste à click/rightClick/commandClick : Maj-clic, Option-clic deviennent des clics simples ; Cmd-clic droit perd Cmd. | Transmettre tous les modificateurs, ou réserver le chemin sémantique aux combinaisons représentables et rejouer les autres en brut. |
| R1-07 | MED | REL-007 | `LayoutMaintainer.swift:1862` | `isFloating` reste nil ; une règle `is_floating = false` ne correspond jamais. | Classification commune, booléen explicite, tests des deux valeurs. |
| R1-08 | MED | REL-030 | `MasterStackLayoutStrategy.swift:88` | Toute largeur observée prime sur le ratio configuré ; `newWindowIDs` ignoré : de nouvelles fenêtres à largeur arbitraire gardent leur largeur. | Géométrie manuelle préservée, géométrie initiale arbitraire (nouvelles fenêtres) : ratio configuré. |
| R1-09 | MED | REL-016 | `DesktopCommands.swift:203` | Fenêtre garée envoyée vers un bureau visible dont la stage est en `float` : le masquage est retiré mais aucun cadre visible n'est fourni, elle reste garée. Le test a une assertion conditionnelle. | Cadre visible de restauration explicite dans le plan ; assertion inconditionnelle. |
| R1-10 | MED | REL-028 | `WindowBookmarkCommands.swift:61`, `CLICommandRouter.swift:268` | « window not visible … bookmark kept » n'est pas reconnu comme échec par `actionExitCode` : code 0 sans focus. | Échec explicite (code non nul) en gardant le signet ; assertion sur le code CLI. |
| R1-11 | MED | REL-018 | `EventSubscriptionService.swift:91` | Ancienne génération introuvable : reprise au début du journal courant sans signaler de rupture ; course `stat` puis réouverture par nom. | Événement de rupture explicite ; limiter la course. |
| R1-12 | MED | REL-005 | `DaemonSnapshot.swift:583` | Stage runtime existante : seul le nom est copié, pas le mode ; desktop existant garde son `activeStageID` de construction. | Fusion complète des métadonnées persistées, en gardant membres live et décisions de focus. |
| R1-13 | MED | REL-010 | `RoadieAX/SystemSnapshotProvider.swift:1059` | Échec de `AXFocusedWindow` (hors cannotComplete) ignoré ; résultat de `setFrontmost` écarté : succès annoncé sans focus. | Traiter ces erreurs ou relire le focus avant d'annoncer le succès. |
| R1-14 | MED | REL-023 | `StageCommands.swift:633` | La seconde transaction retrouve le bureau actuellement actif au lieu du `targetScopeID` calculé et recentre tous les membres de la stage de même id. | Scope exact et membres effectivement transférés ; revérifier l'appartenance. |
| R1-15 | MED | TEST-004 | `BorderController.swift:52` | `groupIndicator` jamais rendu (seuls les tests l'appellent). | Brancher l'indicateur au rendu et tester les données transmises au panneau. |
| R1-16 | MED | TEST-002 | `TargetModeRuntimeControllerTests.swift:136` | Le test multi-écrans ne vérifie pas la fermeture d'activation de la grille (destination du clic). | Capturer et exécuter la fermeture avec émission souris simulée ; vérifier destination et fin de session. |

Avis sur les points incertains : `.max` de `adaptiveMasterRatio` est intentionnel (préserver un
redimensionnement manuel), ne pas le remplacer par `.min` ; `BSPTree.childRects` déborde quand
l'espacement dépasse le conteneur (défaut préexistant, `BSPTree.swift:129`) ; `BSPTree.windowIDs`
quadratique fait partie de PERF-002.
