# Matrice des exigences - spec 049 (specs/049-reglages-macos/spec.md, commit 3dd5563b)

| Exigence | Code | Tests | Verdict |
|---|---|---|---|
| R1 contrôle `macos-window-settings` en `warn` pour 4 réglages | `DaemonHealth.swift:63-102, 153, 157-175` | `activeSettingsGiveAWarningWithLabelsAndLocations` | Implémentée |
| R2 clé absente = défaut de la version | `isEnabled` l. 96-101 | `absentKeyFollowsTheMacOSDefault` | Implémentée (défauts non documentés par Apple) |
| R3 libellé en clair et chemin Réglages Système | `MacOSWindowSetting.all`, message l. 168-173 | contrôle du message | Implémentée, en français seulement |
| R4 `ok` sans réglage gênant ; jamais d'échec | l. 165-167 ; `failed` l. 32-34 | `noDisturbingSettingIsOk`, `warningNeverFailsTheHealthReport` | Implémentée |
| R5 lecture seule | `CFPreferencesCopyAppValue` seul (l. 122) | recherche d'écriture vide | Implémentée |
| Critère : santé installée `ok` chez l'utilisateur | - | - | **Non vérifié** (F1) ; préférences réelles à 0 observées |
