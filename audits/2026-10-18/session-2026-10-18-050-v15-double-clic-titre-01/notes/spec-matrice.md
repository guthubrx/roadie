# Matrice des exigences - spec 050 (specs/050-double-clic-titre/spec.md, commit 8c207d67)

| Exigence | Code | Tests | Verdict |
|---|---|---|---|
| R1 double-clic dans la bande de titre d'une fenêtre gérée et tuilée, hors marges : `toggle maximize` | `TitlebarContextMenuController.swift:225-280` ; `hitTest` existant ; `toggleMaximize(windowID:)` | `roadieActsOnlyOnADoubleClickThatMacOSIgnores`, `interactiveElementsAndFloatingWindowsKeepTheirDoubleClick` (fonctions pures) | Implémentée ; `handleDoubleClick` non testé de bout en bout |
| R2 réglage `double_click_maximize`, défaut `true`, à chaud, indépendant du menu | `Config.swift` (décodage, clé connue) ; config relue à chaque double-clic ; composant démarré par défaut | `settingDefaultsToEnabledAndDecodes` ; `SettingsCatalogTests` | Implémentée |
| R3 aucune action si l'action macOS n'est pas « Ne rien faire » | `handlesDoubleClick` ; `doubleClickAction` | `macOSActionIsReadFromGlobalPreferences`, `absentActionFollowsTheLegacyMinimizeFlag` | Implémentée |
| R4 aucun relevé pour un clic simple ; relevé seulement au double-clic | garde `clickCount == 2` avant `DispatchQueue.main.async` | lecture | Implémentée |
| R5 santé signale le conflit | `DaemonHealth.swift:179, 192-200` | `healthWarnsWhenMacOSAlsoHandlesTheDoubleClick` | Implémentée ; contredit le critère 049 chez l'utilisateur (F1) |
| R6 docs FR/EN et fenêtre des réglages | `docs/{fr,en}/features.md`, `SettingsCatalog.swift:509-512`, CHANGELOG | `SettingsCatalogTests` (182 réglages) | Implémentée |
| Tâche T005 (suite, installation, santé) | - | - | **Non consignée** (F3) |
