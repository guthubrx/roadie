# Plan - 049 Réglages macOS qui gênent le tuilage

1. `Sources/RoadieDaemon/DaemonHealth.swift` : type `MacOSWindowSetting` (domaine, clé,
   version de macOS à partir de laquelle une clé absente vaut « activé », libellé, chemin dans
   Réglages Système) et liste des quatre réglages.
2. `DaemonHealthService` : lecteur de préférences injectable (défaut
   `CFPreferencesCopyAppValue`) et version majeure injectable (défaut
   `ProcessInfo.operatingSystemVersion`). `run()` ajoute le contrôle `macos-window-settings` :
   `warn` si au moins un réglage est actif, sinon `ok`. Jamais `fail`.
3. Docs FR/EN (configuration ou dépannage), CHANGELOG.

Aucun nouveau fichier source ni dépendance. Lecture seule des préférences.
Complexité : O(r), r = 4 réglages.

Défauts macOS retenus (clé absente) :
- `GloballyEnabled` (Stage Manager) : désactivé.
- `EnableTilingByEdgeDrag`, `EnableTopTilingByEdgeDrag` : activés depuis macOS 15.
- `EnableStandardClickToShowDesktop` : activé depuis macOS 14 (« Toujours »).
