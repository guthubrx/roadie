# Plan : session 029 — Redimensionnement fiable et rail cohérent

Branche : `session-029-resize-rail`. Décisions d’intégration du 15 octobre 2026.
Périmètre validé : R1 à R5. Aucune nouvelle dépendance, configuration personnelle modifiée ou publication de version.

## Quatre lots

| Lot | Correction | Propriété et dépendance |
|---|---|---|
| A — Geste | Une seule session en attente. Identité fenêtre/PID/scope capturée et mouvement réel distingué du clic. | Worker resize. |
| B — Rail | Projection pure `StagePresentationOrder`, commune aux cartes, menus et commandes par position. Numéro toujours visible. | Worker rail, fichiers disjoints de A et C. |
| C — Parking | Remplacer le placeholder intact à sa place ; sinon utiliser la position d’origine. Préserver les changements faits pendant l’absence. | Worker parking, fichiers disjoints de A et B. |
| D — Reprises | Mémoriser les placements directs refusés et n’armer la stabilité que pour les écritures abouties. | Parent après gel du lot A, car `LayoutMaintainer` est partagé. Worker retry : tests et proposition de patch temporaire seulement. |

Les compilations et les tests sont centralisés par le parent. Aucun agent ne modifie les sources ou tests pendant une compilation active.

## Intégration retenue

- A : `UserInputActivity` suit `mouseDown → mouseDragged → mouseUp` avec `GestureSession.didDrag`. Un simple clic ne déclenche pas de relecture. Un nouveau geste remplace le précédent. Publication attendue pendant au plus 300 ms une fois le scope traitable ; reprises planifiées par pas de 50 ms. Le plafond absolu reste 2 s depuis le relâchement, même sous une garde de 1,5 s. Aucun retry ne prolonge ce plafond. Les refus de minima, bords extérieurs, dépôts reconnus, plein écran et changements de scope restent en place.
- B : l’ordre représente les membres vivants ou sous grâce de 15 s, ainsi que les stages vides nommés par l’utilisateur. Cette projection ne dépend pas de l’opacité. Les menus affichent par exemple « 2 · Perso ». Les vides automatiques servent de destinations après les entrées visibles. Les autres bureaux gardent leurs destinations persistées non vides ou nommées, car leur relevé vivant n’est pas disponible. Les identifiants CLI bruts restent inchangés.
- C : `StageOrigin.position` suffit pour le repli. Aucun tableau d’ordre redondant. Un champ optionnel `modeAtParking` aide à reconnaître un placeholder intact. Il reste présent tant qu’une copie correspondante existe. La matérialisation après 60 s conserve la position dans le scope hôte. Le retour à l’écran d’origine fonctionne aussi après matérialisation ou une nuit d’absence. Une copie `.restored` reste éligible si son origine existe et que son scope physique ou logique diffère du scope d’origine. Une copie sans origine ou explicitement détachée avec `.native` est respectée.
- D : conserver la mémoire historique `failedFrames` et son expiration de 30 s. Ajouter une mémoire distincte des placements directs refusés, indexée par fenêtre/PID, bundle, scope, cible et cadre observé, liée à l’intention explicite. Un simple écho AX ne la réinitialise pas. Une fenêtre inchangée ne doit pas repartir en boucle après 30 s. Une vraie nouvelle action, géométrie, identité, configuration ou topologie permet une reprise. Ni compteur global ni ralentissement des fenêtres saines.

## Fichiers et tests

| Lot | Sources concernées | Suite dédiée |
|---|---|---|
| A | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/FocusFollowsMouseController.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift | `Spec029ResizeTests` |
| B | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StagePresentationOrder.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailController.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailPanel.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageCommands.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/WindowContextActions.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageCardView.swift | `Spec029RailTests` et adaptations de `TitlebarContextMenuTests` |
| C | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/DisplayParkingService.swift ; structure `StageOrigin` dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageStore.swift | `Spec029DisplayParkingTests` |
| D | /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift, après A | `Spec029RestorationRetryTests` |

Pas de modification de `LayoutTolerance` ni de `TickScheduler` prévue à ce stade. Le lot B réserve dans `StageCardView` une zone au numéro, sans superposition ni coupure aux tailles de police 8, 16 et 48 et à la largeur 90. Réutiliser les mécanismes existants. Les doubles privés des anciens tests ne sont pas accessibles aux nouvelles suites : créer les seuls doubles locaux nécessaires.

## Validation et garde-fous

1. Le parent conserve une preuve rouge sur la logique antérieure, avec des interfaces compatibles, puis une preuve verte par lot. Les fixtures n’exigent pas d’autorisation d’accessibilité réelle.
2. Exécuter les suites ciblées, puis toute la suite avec /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test, qui isole HOME. Baseline avant session : 1 458 tests Swift et 26 tests des scripts.
3. Deux revues indépendantes couvrent correction, complexité et minimalisme. Aucun nouveau catalogue d’événements par défaut. Une ADR n’est nécessaire que si l’intégration introduit une décision architecturale structurante.
4. Installer avec /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/install, conserver le certificat existant, puis redémarrer avec la cible `make restart` et vérifier la santé réelle.
5. Attendre la validation manuelle de l’utilisateur sur la version installée avant commit de code et fusion. Pas d’autre confirmation intermédiaire prévue.

Coûts attendus : attente de geste O(1) en mémoire, projection du rail O(s + m), accès à la mémoire des refus O(1) par commande. L’insertion dans un tableau de stages reste O(s). Les tests doivent vérifier les bornes fonctionnelles ; aucune mesure de latence réelle n’est revendiquée.
