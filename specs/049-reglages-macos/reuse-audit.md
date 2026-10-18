# Audit de reutilisation de l'existant - 049 réglages macOS

## Decision

Statut: PASS
Date: 2026-10-18
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/049-reglages-macos/specs/049-reglages-macos

Conclusion courte: nouveau contrôle ajouté au service de santé existant. Aucune lecture de
préférences macOS n'existe dans Roadie.

## Items du plan

| Item | Existant | Classement | Décision |
|---|---|---|---|
| Contrôle `macos-window-settings` | `DaemonHealthService.run` (`Sources/RoadieDaemon/DaemonHealth.swift:85`) | OK | ETENDRE |
| Lecture des préférences | aucune (`rg "CFPreferencesCopyAppValue\|UserDefaults(suiteName"` vide) | OK aucun equivalent | CREER, dans `DaemonHealth.swift` |
| Niveau d'alerte | `DaemonHealthLevel.warn` | OK | REUTILISER |

## Gate avant tasks

- [x] Chaque item a une ligne de résultat.
- [x] Aucune duplication évidente non arbitrée.
- [x] Aucun refactor du plan requis.
