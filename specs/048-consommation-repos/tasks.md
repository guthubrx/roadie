# Tâches

- [x] T001 Mesurer l'état de départ au repos (`mesures/avant.json`).
- [x] T002 Tests rouges A-01 : relevé lecteur réutilisé sans changement jusqu'au filet (1 s dans la version initiale, 2 s après revue, ADR 015), refusé après un changement ou au-delà du filet ; commandes inchangées à 150 ms ; demande de passe hors filet incrémente la génération (`Tests/RoadieDaemonTests/Spec048QuietReaderTests.swift`).
- [x] T003 Implémenter A-01 dans `Sources/RoadieDaemon/DaemonSnapshot.swift` et `Sources/RoadieDaemon/TickScheduler.swift`.
- [x] T004 Tests puis implémentation C-01 : énumération seulement si un identifiant manque (`Sources/RoadieDaemon/RailThumbnailStore.swift`).
- [x] T005 Implémenter C-02 : statut d'enregistrement mémorisé (`Sources/RoadieDaemon/RailController.swift`).
- [x] T006 Tests puis implémentation C-03 : vignettes mises à jour en place (`RailController.swift`, `RailPanel.swift`, `StageCardView.swift`).
- [x] T007 Suite complète, revue indépendante, ADR 015.
- [x] T008 Installer, redémarrer, santé ; mesurer après (`mesures/apres.json`) ; publier avant/après.
- [ ] T009 Consigner, committer, intégrer sur main, pousser, nettoyer.
