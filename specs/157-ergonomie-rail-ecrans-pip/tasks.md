# Tâches — Spec 157

- [x] **T1** : Ajouter les réglages `tiling.float_picture_in_picture` (défaut `true`) et `fx.rail.show_app_icons_row` (défaut `true`) dans `Config.swift`, `RailSettings.swift`, `RailVisualConfig.swift`, `SettingsCatalog.swift`, `SettingsCatalogRail.swift`, `SettingsCatalogTests.swift`.
- [x] **T2** : Implémenter la rangée d'icônes d'applications côte à côte sous chaque carte non vide du NavRail dans `StageCardView.swift` sans altérer les indicateurs plein écran natif / zoom, ni casser la géométrie/légendes existantes.
- [x] **T3** : Implémenter `DisplayCommandService.swap`, `StageCommandService.pruneEmpty`, le routage CLI (`display swap`, `stage prune-empty`), le menu contextuel du NavRail (`Égaliser les proportions`, `Échanger avec l'écran…`, `Nettoyer les stages vides`) et les 3 commandes dans le lanceur (`LauncherSystemCommands.swift`).
- [x] **T4** : Implémenter la détection Picture-in-Picture dans `DaemonSnapshot.baseTilingDecision` (conditionnée par `tiling.float_picture_in_picture`, surchargeable par règle utilisateur).
- [x] **T5** : Écrire les tests unitaires dédiés (`Tests/RoadieDaemonTests/Spec157ErgonomieTests.swift`), mettre à jour `docs/fr/features.md`, `docs/en/features.md`, `CHANGELOG.md` et `.specify/memory/sessions/journal.md`.
- [ ] **T6** : Exécuter `./scripts/test --no-parallel && python3 -I -B -m unittest discover -s scripts/tests`, revue indépendante Bridget jusqu'à `Approuvé`, livraison sur `main`, installation signée `roadied-cert`, redémarrage vérifié 5/5 et ménage complet.
