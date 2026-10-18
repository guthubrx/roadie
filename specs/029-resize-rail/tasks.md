# Tâches : session 029 — Redimensionnement fiable et rail cohérent

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

Les tâches restent en attente jusqu’à validation centralisée. Le parent tient les résultats rouge → vert, lance tous les tests et décide les commits. Aucun agent n’édite les sources ou tests pendant une compilation. Aucun commit de code ni fusion avant l’essai utilisateur de la version installée.

## Préparation

- [x] T001 Périmètre de la session validé et artefacts préparés.
- [x] T002 Aligner les décisions sur le diagnostic et les interfaces réelles : session de geste unique, projection `StagePresentationOrder`, placeholder et position existants, mémoire distincte des refus directs.

## Lot A — Geste fiable (R1, R5)

Propriétaire : worker resize. Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/FocusFollowsMouseController.swift et zone gestes de /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift. Tests : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029ResizeTests.swift.

- [x] T010 Reproduire en rouge la taille publiée après relâchement et le geste consommé sous garde ; garder une preuve compatible avec l’ancienne logique.
- [x] T011 Capturer `didDrag`, fenêtre/PID/scope ; conserver une seule attente remplaçable. Borner à 300 ms actifs, lectures planifiées par pas de 50 ms, plafond absolu de 2 s depuis le relâchement, sans prolongation.
- [x] T012 Vérifier en vert les deux défauts et les protections : clic simple, nouveau geste, changement d’identité/scope, minima, bords extérieurs, dépôt, plein écran et expiration sans échéance résiduelle. Geler les fichiers avant intégration D.

## Lot B — Rail cohérent (R2, R5)

Propriétaire : worker rail. Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StagePresentationOrder.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailController.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/RailPanel.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCommands.swift , /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/WindowContextActions.swift et /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageCardView.swift. Tests : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029RailTests.swift et adaptations ciblées de /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift.

- [x] T020 Reproduire en rouge les divergences de positions entre cartes, menus et commandes.
- [x] T021 Brancher la projection commune : vivants, grâce de 15 s et vides nommés. Badge toujours visible, menus « 2 · Perso », vides automatiques en repli. Garder les destinations persistées non vides ou nommées des autres bureaux et les identifiants CLI bruts.
- [x] T022 Vérifier en vert les positions, la grâce, les stages vides nommés, les autres bureaux, les noms et identifiants inchangés. Aucun effet de l’opacité sur les destinations. Les quatre tests `Spec029StageMoveIdentityTests` vérifient aussi les noms automatiques après identifiant final, les noms personnels et les destinations vides personnalisées préservées. Réserver la zone du badge sans superposition ni coupure aux polices 8/16/48 et à la largeur 90.

## Lot C — Retour d’écran (R3, R5)

Propriétaire : worker parking. Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DisplayParkingService.swift et structure `StageOrigin` de /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageStore.swift. Tests : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029DisplayParkingTests.swift.

- [x] T030 Reproduire en rouge le retour en fin de liste et le retour perdu après matérialisation.
- [x] T031 Remplacer le placeholder intact en place ; repli sur `position` si absent pour une copie encore `.parked`. Réutiliser le schéma existant sans nouveau champ. Préserver placeholder et origine tant qu’une copie correspondante existe, sans écraser renommage ni mode modifié.
- [x] T032 Vérifier en vert retour court, après 60 s et après une nuit ; `.restored` revenant seulement avec son placeholder `.parked` dans le bureau/écran d’origine ; ancienne copie sans placeholder respectée ; déplacement explicite détachant le stage ; copie native ou sans origine respectée ; ordre utilisateur, compatibilité des anciens fichiers et idempotence. Corriger localement le diagnostic d’origine absente vide, sans nouveau format général.

## Lot D — Refus bornés (R4, R5), après gel A

Propriétaire de l’intégration : parent. Worker retry : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029RestorationRetryTests.swift et proposition de patch temporaire uniquement. Source partagée : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift.

- [x] T040 Reproduire en rouge les refus répétés hors arbre, le contournement par le focus et la stabilité réarmée par les échecs.
- [x] T041 Intégrer une mémoire distincte des refus directs, avec fenêtre/PID/bundle/scope/cible/cadre observé, liée à l’intention explicite. Garder le contrat historique de 30 s. Ne pas réinitialiser sur un simple écho AX ni sur une progression monotone différée ; un geste confirmé traité libère le budget, un clic simple ne le renouvelle pas. N’armer la stabilité que pour les écritures abouties, pour toutes les commandes.
- [x] T042 Vérifier en vert les 22 scénarios prévus, dont les refus inchangés après 30 s en modes libre et `spatialBsp`, les reprises après changement réel et les fenêtres saines non ralenties. Aucune échéance passée maintenue en boucle.

## Validation commune et livraison

- [x] T050 Le parent lance les suites ciblées puis /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/test et les 26 tests des scripts. Consigner les résultats et limites ; aucun `swift test` direct. Avant le premier essai : 1 514 tests Swift dans 162 suites, tous verts en 8,422 s, dans /private/tmp/roadie-029-final-tests.log. Après reprise : 1 520 tests dans 163 suites, tous verts en 8,889 s, dans /private/tmp/roadie-029-resize-followup-full-tests.log. Après récupération de callback perdu : 1 526 tests dans 163 suites, tous verts en 7,170 s, dans /private/tmp/roadie-029-release-recovery-full-tests.log. Les scripts inchangés ont leurs 26 tests verts au contrôle précédent en 23,555 s. La fixture dépendant de la configuration personnelle reçoit une configuration explicite sans workspaces.
- [x] T051 Réaliser deux revues indépendantes et traiter les remarques ciblées. Vérifier correction, complexité, minimalisme et charge future. Tous les constats fonctionnels des quatre tours avec deux relecteurs sont traités. Les points non bloquants sont justifiés dans le journal de validation. ADR seulement si l’architecture évolue réellement.
- [x] T052 Installer avec /Users/moi/Nextcloud/10.Scripts/39.roadie/scripts/install, conserver le certificat existant, redémarrer avec `make restart` et vérifier la santé réelle. Première installation signée, PID 53846, quatre contrôles verts et configuration inchangée. Essai de redimensionnement ensuite non concluant ; cette étape historique ne valide pas la nouvelle installation de T055.
- [ ] T053 Obtenir la validation manuelle de la version installée selon /Users/moi/Nextcloud/10.Scripts/39.roadie/specs/029-resize-rail/quickstart.md.
- [x] T055 Corriger la course entre relâchement physique et callback mouseUp, avec la même garde dans le scheduler, le mainteneur et les tests. Vérifier les poignées devant un fond inéligible, sans viser une fenêtre derrière un vrai obstacle. Suite après reprise verte : 1 520 tests dans 163 suites en 8,889 s. Revue ciblée 5 terminée sans blocage prouvé. Ajouter le repli de callback perdu avec tests rouges avant patch : seuil de 300 ms depuis le premier relâchement physique observé, clôture et consommation uniques, aucun timeout pendant un maintien physique, aucun rejeu sur callback tardif. Consultation par événements ou filet périodique, sans promesse de délai exact. Preuve rouge : 20 tests, une suite, 16 constats dans /private/tmp/roadie-029-release-recovery-red-tests.log ; suite corrigée : 1 526 tests dans 163 suites verts en 7,170 s. Installation finale signée terminée dans /private/tmp/roadie-029-release-recovery-install.log, puis redémarrage terminé, daemon PID 60128 et quatre contrôles de santé réussis. Certificat et configuration conservés. Nouvel essai utilisateur requis via T053 ; aucune conclusion de résolution native avant sa réponse.
- [ ] T054 Consigner les preuves, mettre les statuts à jour, committer, fusionner et nettoyer les branches inutiles. Aucun changement de version ni publication de release.

Dépendances : A, B et C peuvent avancer en parallèle. D attend le gel de A. La validation commune attend les quatre lots.
