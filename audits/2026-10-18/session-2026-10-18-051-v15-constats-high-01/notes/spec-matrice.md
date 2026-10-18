# Matrice des exigences - spec 051 (specs/051-constats-high/spec.md, commit 38f69a6a)

| Exigence | Code / appelants | Tests | Verdict |
|---|---|---|---|
| R1 A-03 bundle une fois par processus et par relevé ; A-02 index AX réutilisé s'il couvre | `SystemSnapshotProvider.swift:748, 788-794, 826-830, 853-855` | `Spec051WindowIndexReuseTests` (fonction pure) | Implémentée. A-03 sans test ; A-02 testé hors du relevé réel |
| R2 A-04 chemin des règles mémorisé | `ConfigReloadService.swift:240-254` | `generatedRulesPathIsMemoizedWithTheSameValue` (égalité, ne prouve pas la mémoire) | Implémentée |
| R3 A-05 au plus un réveil par seconde si désactivé | `FocusFollowsMouseController.swift:26-51` | `disabledFocusFollowsMouseWakesOncePerSecond` (fonction pure) | Implémentée ; 1 s avant la première réaction après activation (documenté) |
| R4 B-01 pas de verrou exclusif sans changement | `DaemonSnapshot.swift:404-419` | `unchangedSnapshotDoesNotWaitForTheStateLock` (vrai flock) | Implémentée |
| R5 C-05 clic hors barre de titre sans relevé | Rail : `RailController.swift:401-416` ; session de geste : `main.swift:429` | `clickOutsideAManagedTitleBandStartsNoDragContext` (fonction pure) | **Contredite en mode `run`** (F1) ; implémentée pour le rail seul |
| R6 C-06 rail replié sans vignettes, reprise au dépliage | `RailController.swift:1008-1010, 1058` ; `RailPanel.swift:126-134, 233-240` | `collapsedRailReportsItsRevealOnce` | Implémentée ; exclusion des captures non testée |
| R7 D-03 un seul relevé par commande en arbre | `WindowCommands.swift:200-209` | `treeMoveCommandScansOnlyOnce`, `treeResizeCommandScansOnlyOnce` | Implémentée ; `warp` non testé ; cadres appliqués non vérifiés par ces tests |
| R8 D-02 non modifié, décision demandée | `research.md` (recommandation), `validation.md` (décision utilisateur) | - | Conforme |
| R9 comportements et budgets conservés, suite verte | - | 1 731 tests / 205 suites | Implémentée |
| Critère : mesure avant/après publiée | aucun fichier `mesures/` | - | **Absent** (F3, T007 ouverte) |
