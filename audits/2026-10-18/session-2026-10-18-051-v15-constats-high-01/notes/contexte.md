# Preuve de contexte - audit V15 readonly, session 051 (constats HIGH restants)

Racine figée : `/private/tmp/roadie-audit-051` (worktree détaché, commit 38f69a6a799aa3a9767ca042715a7d436e804a4b).
Revue différentielle : base ab9b28e958fb246525e5e80c77dafa11c70288b5 (048). Mode readonly, un cycle.
Auditeur : Claude (Opus), même agent que l'orchestration, `independent=false`. Aucune revue indépendante.

## Biens à protéger
- Exactitude du relevé des fenêtres (index AX, bundle, état persisté `stages.json`).
- Coût CPU au repos et réactivité du fil principal (clics, commandes en arbre).
- Intégrité de `stages.json` sous transactions concurrentes (B-01).

## Acteurs et points d'entrée
- Relevé `LiveSystemSnapshotProvider.windows()` (A-02, A-03), tous processus.
- `ConfigReloadService.stamp(for:)` (A-04), appelé à chaque lecture de config.
- Minuterie `FocusFollowsMouseController` (A-05).
- `SnapshotService.snapshot(...)` producteur avec `persistStateChanges` (B-01).
- Clic gauche : moniteurs du rail (`RailController.swift:231, 245`) et de `UserInputActivity`
  (`FocusFollowsMouseController.swift:140`), branché sur la session de geste du tiler (`main.swift:427-445`).
- Commandes en arbre `WindowCommandService` move/warp/resize (D-03), via le socket du daemon.
- Mode par défaut `roadied run` : rail et tiler dans le même processus, événements en direct
  (`main.swift:479-489`) ; état de relevé partagé par chemin d'état (`DaemonSnapshot.swift:159, 2445`).

## Invariants vérifiés à la lecture
1. A-02 : l'index AX mémorisé n'est réutilisé que s'il couvre toutes les fenêtres CG demandées,
   non vides (`SystemSnapshotProvider.swift:826-830`) ; l'observateur AX l'invalide sur création,
   destruction et fin d'application (`AXWindowEventObserver.swift:158-161, 273`).
2. A-03 : identifiant de bundle mémorisé par PID et par relevé uniquement (variable locale).
3. A-04 : `generatedRulesPath` ne dépend que du chemin (et de HOME) (`Config.swift:1177-1182`) ;
   mémoire sous `OSAllocatedUnfairLock`.
4. B-01 : réconciliation d'une copie lue sans verrou ; transaction exclusive seulement si l'état
   change ; dans la transaction, résultat réutilisé si l'état persistant égale la copie lue, sinon
   nouvelle réconciliation (`DaemonSnapshot.swift:404-419`). `reconcile` est pure de (état, entrée).
5. D-03 : `applyTreeScope(using:)` relit l'arbre muté dans `stageStore.state()` (`layoutPlan`,
   `DaemonSnapshot.swift:1834`) ; seules les fenêtres viennent du relevé d'entrée.
6. C-05 : bande de 44 points identique à `dragSourceWindow` ; cadres gérés recalculés à chaque
   rendu du rail (`RailController.swift:981`, avant la garde des écrans changés).
7. C-06 : `setCollapsed` est gardé (`isCollapsed != collapsed`) : pas de boucle dépliage -> rendu.

## Fichiers lus
Diff complet (8 sources, 4 tests) ; `SystemSnapshotProvider.swift:505-660, 735-880` ;
`AXWindowEventObserver.swift:140-165, 262-280` ; `DaemonSnapshot.swift:150-312, 340-440, 1321-1352, 1447-1480, 1810-1840, 2428-2450` ;
`StageStore.swift:170-220` ; `JSONPersistence.swift` ; `RailController.swift:225-260, 370-420, 896-1000, 1050-1060, 1110-1150, 1200-1230` ;
`RailPanel.swift:120-245` ; `DropPreviewController.swift:30-40, 128-135, 505-570, 640-660` ;
`FocusFollowsMouseController.swift` (entier) ; `TitlebarContextMenuController.swift:170-240` ;
`main.swift:170-190, 330-520` ; `Config.swift:1170-1190` ; spec, plan, tasks, research, reuse-audit, validation.

## Zones non lues et inconnues
- Coût réel d'un relevé complet (non mesuré ici ; aucune mesure de la 051 dans le commit).
- Processus lecteurs autonomes (mode modulaire) : validité d'un index AX ancien non observée.
- Comportement visuel du rail replié/déplié : non observé (pas d'accès au bureau).
