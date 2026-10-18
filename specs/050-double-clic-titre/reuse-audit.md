# Audit de reutilisation de l'existant - 050 double-clic

## Decision

Statut: PASS
Date: 2026-10-18
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/050-double-clic-titre/specs/050-double-clic-titre

Conclusion courte: le double-clic réutilise le test de barre de titre du menu contextuel,
la maximisation existante et le contrôle de santé de la session 049.

## Items du plan

| Item | Existant | Classement | Décision |
|---|---|---|---|
| Test de barre de titre | `TitlebarContextMenuController.hitTest` | OK | REUTILISER |
| Action | `WindowCommandService.toggleMaximize(windowID:)` | OK | REUTILISER |
| Lecture de l'action macOS | lecteur de préférences de `DaemonHealthService` (049) | OK | ETENDRE |
| Réglage | `TitlebarContextMenuConfig` | OK | ETENDRE |
| Moniteur de clic | moniteurs `rightMouseDown` du même contrôleur | OK | ETENDRE |

## Gate avant tasks

- [x] Chaque item a une ligne de résultat.
- [x] Aucune duplication évidente non arbitrée.
- [x] Aucun refactor du plan requis.
