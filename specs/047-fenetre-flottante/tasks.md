# Tâches

- [x] T001 Écrire en rouge les tests : visibilité `.stage`, bascule tuilée vers flottante et retour, épinglage desktop retiré par la bascule, absence de fenêtre active, sortie de l'arbre, persistance de `pinScope = "stage"`, aide CLI.
- [x] T002 Ajouter `WindowPinScope.stage` et sa branche de visibilité dans `Sources/RoadieDaemon/StageStore.swift`.
- [x] T003 Ajouter `WindowContextActions.toggleFloating(windowID:)` et l'action `.floatStage` dans `Sources/RoadieDaemon/WindowContextActions.swift` et `Sources/RoadieDaemon/TitlebarContextMenuController.swift`.
- [x] T004 Brancher `roadie toggle floating` dans `Sources/RoadieDaemon/CLICommandRouter.swift` ; mettre à jour le libellé du menu « Fenêtre ».
- [x] T005 Aligner `docs/fr/features.md`, `docs/en/features.md`, `CHANGELOG.md` et le test d'aide.
- [x] T006 Lancer les tests ciblés puis la suite complète ; revue indépendante.
- [x] T007 Installer la version signée, redémarrer, vérifier la santé et la commande installée.
- [x] T008 Consigner la validation, committer, intégrer sur main, pousser et nettoyer.
- [x] T009 Revue 1 : format compatible avec les versions antérieures, tests de masquage, restauration, tuileur, relecture et routage.
- [x] T010 Essai réel : routage de `toggle floating` vers le daemon, réinstallation et aller-retour vérifié.
