# Plan : session 029 — Redimensionnement fiable et rail cohérent

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

Branche : `session-029-resize-rail`. Décisions d’intégration du 15 octobre 2026.
Périmètre validé : R1 à R5. Aucune nouvelle dépendance, configuration personnelle modifiée ou publication de version.

## Quatre lots

| Lot | Correction | Propriété et dépendance |
|---|---|---|
| A — Geste | Une seule session en attente. Identité fenêtre/PID/scope capturée et mouvement réel distingué du clic. | Worker resize. |
| B — Rail | Projection pure `StagePresentationOrder`, commune aux cartes, menus et commandes par position. Numéro toujours visible. | Worker rail, fichiers disjoints de A et C. |
| C — Parking | Remplacer le placeholder intact à sa place. Pour une copie encore `.parked`, garder le repli sur la position d’origine. Préserver les changements faits pendant l’absence. | Worker parking, fichiers disjoints de A et B. |
| D — Reprises | Mémoriser les placements directs refusés et n’armer la stabilité que pour les écritures abouties. | Parent après gel du lot A, car `LayoutMaintainer` est partagé. Worker retry : tests et proposition de patch temporaire seulement. |

Les compilations et les tests sont centralisés par le parent. Aucun agent ne modifie les sources ou tests pendant une compilation active.

## Intégration retenue

- A : `UserInputActivity` suit `mouseDown → mouseDragged → mouseUp` avec `GestureSession.didDrag`. Un simple clic ne déclenche pas de relecture. Un nouveau geste remplace le précédent. Publication attendue pendant au plus 300 ms une fois le scope traitable ; reprises planifiées par pas de 50 ms. Le plafond absolu reste 2 s depuis le relâchement, même sous une garde de 1,5 s. Aucun retry ne prolonge ce plafond. Les refus de minima, bords extérieurs, dépôts reconnus, plein écran et changements de scope restent en place. La garde commune `blocksLayout` combine bouton physique pressé OU session souris ouverte, jusqu’au callback normal de relâchement ou au repli de callback perdu : seuil de 300 ms depuis le premier relâchement physique observé, clôture unique puis consommation par la passe. Un bouton maintenu ne subit aucun timeout et un callback tardif ne rejoue pas le geste. Le repli utilise les événements ou le filet périodique existant, sans échéance exacte à 300 ms. Le picker accepte les poignées devant le premier intérieur inéligible, mais jamais une fenêtre derrière un vrai obstacle ; le choix strict du focus reste inchangé.
- B : l’ordre représente les membres vivants ou sous grâce de 15 s, ainsi que les stages vides nommés par l’utilisateur. Cette projection ne dépend pas de l’opacité. Les menus affichent par exemple « 2 · Perso ». Les vides automatiques servent de destinations après les entrées visibles. Les autres bureaux gardent leurs destinations persistées non vides ou nommées, car leur relevé vivant n’est pas disponible. Les identifiants CLI bruts restent inchangés.
- C : utiliser les champs existants de `StageOrigin`, sans nouveau champ. Remplacer le placeholder intact en place ; une copie encore `.parked` conserve le repli sur la position historique si ce placeholder manque. Après matérialisation, une copie `.restored` ne revient que si un placeholder `.parked` correspondant existe toujours dans son bureau et son écran d’origine, reconnu par identité physique ou logique. Une ancienne copie `.restored` sans ce témoin reste dans son scope actuel : ses seules métadonnées ne prouvent plus un retour attendu. La matérialisation conserve la place dans le scope hôte et permet un retour après 60 s ou une nuit si ce lien subsiste. Un déplacement explicite vers un écran détache le stage : `.native`, `origin`, `host` et `restoredAt` effacés. Les modifications de nom ou de mode restent conservées. Si le mode d’origine d’un ancien placeholder est inconnu, conserver celui-ci par prudence. Lors d’un déplacement, capturer la nature automatique du nom avant détachement et ne réécrire ce nom qu’après le choix de l’identifiant final. Préserver une destination vide nommée, de mode différent ou avec arbre explicite en allouant un autre identifiant.
- D : conserver la mémoire historique `failedFrames` et son expiration de 30 s. Ajouter une mémoire distincte des placements directs refusés, indexée par fenêtre/PID, bundle, scope, cible et cadre observé, liée à l’intention explicite. Un simple écho AX ne la réinitialise pas. Une fenêtre inchangée ne doit pas repartir en boucle après 30 s. Une vraie nouvelle action, géométrie externe, identité, configuration ou topologie permet une reprise. Une progression monotone différée vers la cible garde le budget ; un geste confirmé puis traité le libère. Un clic simple ne renouvelle ni génération ni budget. Ni compteur global ni ralentissement des fenêtres saines.

## Fichiers et tests

| Lot | Sources concernées | Suite dédiée |
|---|---|---|
| A | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/FocusFollowsMouseController.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/TickScheduler.swift | `Spec029ResizeTests`, `Spec029PickerOcclusionTests` |
| B | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StagePresentationOrder.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailController.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailPanel.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowContextActions.swift ; /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCardView.swift | `Spec029RailTests`, `Spec029StageMoveIdentityTests` et adaptations de `TitlebarContextMenuTests` |
| C | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DisplayParkingService.swift ; réutilisation de `StageOrigin` sans changement de schéma | `Spec029DisplayParkingTests` |
| D | /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift, après A | `Spec029RestorationRetryTests` |

La reprise après essai non concluant ajoute la même garde `UserInputActivity.blocksLayout` au scheduler et au mainteneur. Aucune modification de `LayoutTolerance`. Le lot B réserve dans `StageCardView` une zone au numéro, sans superposition ni coupure aux tailles de police 8, 16 et 48 et à la largeur 90. Réutiliser les mécanismes existants. Les doubles privés des anciens tests ne sont pas accessibles aux nouvelles suites : créer les seuls doubles locaux nécessaires.

## Validation et garde-fous

1. Le parent conserve une preuve rouge sur la logique antérieure, avec des interfaces compatibles, puis une preuve verte par lot. Les fixtures n’exigent pas d’autorisation d’accessibilité réelle.
2. Exécuter les suites ciblées, puis toute la suite avec /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/test, qui isole HOME. Baseline avant session : 1 458 tests Swift et 26 tests des scripts.
3. Deux revues indépendantes couvrent correction, complexité et minimalisme. Aucun nouveau catalogue d’événements par défaut. Une ADR n’est nécessaire que si l’intégration introduit une décision architecturale structurante.
4. Installer avec /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/install, conserver le certificat existant, puis redémarrer avec la cible `make restart` et vérifier la santé réelle.
5. Attendre la validation manuelle de l’utilisateur sur la version installée avant commit de code et fusion. Pas d’autre confirmation intermédiaire prévue.

Coûts attendus : attente de geste O(1) en mémoire, projection du rail O(s + m), accès à la mémoire des refus O(1) par commande. L’insertion dans un tableau de stages reste O(s). Les tests doivent vérifier les bornes fonctionnelles ; aucune mesure de latence réelle n’est revendiquée.

## Reprise après premier essai

Le premier essai utilisateur du redimensionnement reste non concluant malgré les tests initiaux. Les événements à 05:41:38 CEST montrent un tick AX avant le callback `mouseUp` : la garde de runtime ne suivait pas la session encore ouverte, contrairement au harnais. Une seconde reproduction révèle des poignées proches du cadre ignorées à cause d’éléments décoratifs derrière leur fenêtre parente. Ces deux causes sont couvertes par des tests rouges puis verts.

Après correction, la suite complète passe : 1 520 tests dans 163 suites, en 8,889 s. La revue ciblée 5 est terminée sans blocage prouvé. Le garde-fou de callback perdu reproduit 16 constats dans 20 tests sur la baseline sans récupération. La suite corrigée passe avec 1 526 tests dans 163 suites en 7,170 s. L’installation finale signée et son redémarrage sont terminés ; les quatre contrôles de santé passent avec le daemon PID 60128. Le nouvel essai utilisateur reste requis avant de conclure à la résolution native. Le premier daemon installé PID 53846 ne représente pas cette nouvelle installation.
