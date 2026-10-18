# Plan - 050 Double-clic sur la barre de titre

1. `Sources/RoadieCore/Config.swift` : `TitlebarContextMenuConfig.doubleClickMaximize`
   (`double_click_maximize`, défaut `false`), clé connue du chargeur.
2. `Sources/RoadieDaemon/TitlebarContextMenuController.swift` : moniteur global
   `leftMouseDown` filtré sur `clickCount == 2` avant tout relevé ; si le réglage est actif et
   l'action macOS vaut « Ne rien faire », test de la barre de titre par `hitTest` (mêmes
   hauteur, marges et filtres), puis `WindowCommandService.toggleMaximize(windowID:)`.
3. Action macOS lue par `MacOSWindowSetting.doubleClickAction(read:)` dans
   `Sources/RoadieDaemon/DaemonHealth.swift` : `AppleActionOnDoubleClick` du domaine global ;
   clé absente : `AppleMiniaturizeOnDoubleClick` vrai = réduire, sinon agrandir (défaut macOS).
4. Santé : `macOSWindowSettingsCheck` reçoit l'état du réglage Roadie et ajoute le conflit.
5. Catalogue des réglages (`SettingsCatalog.swift`), exemple, docs FR/EN, CHANGELOG.

Aucun nouveau fichier source ni dépendance. Un clic simple ne coûte qu'un test d'entier.
