# Tâches : session 029 — Redimensionnement fiable et rail cohérent

Les tâches restent en attente jusqu’à validation centralisée. Le parent tient les résultats rouge → vert, lance tous les tests et décide les commits. Aucun agent n’édite les sources ou tests pendant une compilation. Aucun commit de code ni fusion avant l’essai utilisateur de la version installée.

## Préparation

- [x] T001 Périmètre de la session validé et artefacts préparés.
- [x] T002 Aligner les décisions sur le diagnostic et les interfaces réelles : session de geste unique, projection `StagePresentationOrder`, placeholder et position existants, mémoire distincte des refus directs.

## Lot A — Geste fiable (R1, R5)

Propriétaire : worker resize. Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/FocusFollowsMouseController.swift et zone gestes de /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift. Tests : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029ResizeTests.swift.

- [ ] T010 Reproduire en rouge la taille publiée après relâchement et le geste consommé sous garde ; garder une preuve compatible avec l’ancienne logique.
- [ ] T011 Capturer `didDrag`, fenêtre/PID/scope ; conserver une seule attente remplaçable. Borner à 300 ms actifs, lectures planifiées par pas de 50 ms, plafond absolu de 2 s depuis le relâchement, sans prolongation.
- [ ] T012 Vérifier en vert les deux défauts et les protections : clic simple, nouveau geste, changement d’identité/scope, minima, bords extérieurs, dépôt, plein écran et expiration sans échéance résiduelle. Geler les fichiers avant intégration D.

## Lot B — Rail cohérent (R2, R5)

Propriétaire : worker rail. Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StagePresentationOrder.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailController.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/RailPanel.swift, /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageCommands.swift , /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/WindowContextActions.swift et /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageCardView.swift. Tests : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029RailTests.swift et adaptations ciblées de /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift.

- [ ] T020 Reproduire en rouge les divergences de positions entre cartes, menus et commandes.
- [ ] T021 Brancher la projection commune : vivants, grâce de 15 s et vides nommés. Badge toujours visible, menus « 2 · Perso », vides automatiques en repli. Garder les destinations persistées non vides ou nommées des autres bureaux et les identifiants CLI bruts.
- [ ] T022 Vérifier en vert les positions, la grâce, les stages vides nommés, les autres bureaux, les noms et identifiants inchangés. Aucun effet de l’opacité sur les destinations. Réserver la zone du badge sans superposition ni coupure aux polices 8/16/48 et à la largeur 90.

## Lot C — Retour d’écran (R3, R5)

Propriétaire : worker parking. Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/DisplayParkingService.swift et structure `StageOrigin` de /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageStore.swift. Tests : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029DisplayParkingTests.swift.

- [ ] T030 Reproduire en rouge le retour en fin de liste et le retour perdu après matérialisation.
- [ ] T031 Remplacer le placeholder intact en place ; repli sur `position` si absent. Ajouter seulement `modeAtParking` optionnel si nécessaire. Préserver placeholder et origine tant qu’une copie correspondante existe, sans écraser renommage ni mode modifié.
- [ ] T032 Vérifier en vert retour court, après 60 s et après une nuit ; `.restored` encore ailleurs que l’origine ; copie native ou sans origine respectée ; ordre utilisateur, compatibilité des anciens fichiers et idempotence. Corriger localement le diagnostic d’origine absente vide, sans nouveau format général.

## Lot D — Refus bornés (R4, R5), après gel A

Propriétaire de l’intégration : parent. Worker retry : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029RestorationRetryTests.swift et proposition de patch temporaire uniquement. Source partagée : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift.

- [ ] T040 Reproduire en rouge les refus répétés hors arbre, le contournement par le focus et la stabilité réarmée par les échecs.
- [ ] T041 Intégrer une mémoire distincte des refus directs, avec fenêtre/PID/bundle/scope/cible/cadre observé, liée à l’intention explicite. Garder le contrat historique de 30 s. Ne pas réinitialiser sur un simple écho AX ; n’armer la stabilité que pour les écritures abouties.
- [ ] T042 Vérifier en vert les 20 scénarios prévus, dont les refus inchangés après 30 s en modes libre et `spatialBsp`, les reprises après changement réel et les fenêtres saines non ralenties. Aucune échéance passée maintenue en boucle.

## Validation commune et livraison

- [ ] T050 Le parent lance les suites ciblées puis /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test et les 26 tests des scripts. Consigner les résultats et limites ; aucun `swift test` direct.
- [ ] T051 Réaliser deux revues indépendantes et traiter les remarques ciblées. Vérifier correction, complexité, minimalisme et charge future. ADR seulement si l’architecture évolue réellement.
- [ ] T052 Installer avec /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/install, conserver le certificat existant, redémarrer avec `make restart` et vérifier la santé réelle.
- [ ] T053 Obtenir la validation manuelle de la version installée selon /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/029-resize-rail/quickstart.md.
- [ ] T054 Consigner les preuves, mettre les statuts à jour, committer, fusionner et nettoyer les branches inutiles. Aucun changement de version ni publication de release.

Dépendances : A, B et C peuvent avancer en parallèle. D attend le gel de A. La validation commune attend les quatre lots.
