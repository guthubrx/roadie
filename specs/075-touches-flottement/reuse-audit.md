# Audit de réutilisation 075

Statut : `OK`. Primitive `speckit-audit-existing` utilisée en repli manuel (recherches `rg`).

| Élément du plan | Existant trouvé | Issue |
|---|---|---|
| Lecture des modificateurs tenus | `FocusFollowsMouseController` (tap global, autre rôle) | CRÉER `onFlags` dans `SearchInputPanel` : le panneau reçoit déjà ses événements, pas de tap |
| Retour avec ⌥/⌃ | `SearchKeyInput.Kind.confirm(shift:command:)` | RÉUTILISER, étendre de `option`, `control` |
| ⌘1 à ⌘9 | `SearchInputPanel.performKeyEquivalent` (⌘ + lettre) | RÉUTILISER, ajouter les chiffres |
| Variantes | aucun équivalent (`Variant` ailleurs = REL-021, sans lien) | CRÉER `LauncherVariant` dans `LauncherActions.swift` (3 touches × 4 objets) |
| Raccourci des verbes | `TargetSearchHotkey`, déjà instancié pour la vue d'ensemble (`OverviewController.swift:57`) | RÉUTILISER, seconde instance |
| `roadie target actions` | `CLICommandRouter` `target search` (`queueTargetModeRuntimeCommand`) | RÉUTILISER le même chemin |
| Règles « toujours » | `WindowRuleAffinityService` (fichier généré, relecture avant écriture) | RÉUTILISER, étendre ; règle unique par application (research R4) |
| Menu Fenêtre | `TitlebarContextMenuController.addWindowSubmenu`, `WindowContextActionKind` | RÉUTILISER, nouvelles entrées |
| Faire flotter cette fenêtre | `WindowContextActions.toggleFloating` (SPEC-047) | RÉUTILISER |
| Envoyer vers / nouvelle stage | `WindowContextActions.assign`, `StageCommandService.createStage` | RÉUTILISER |
| Recherche web | aucun | CRÉER clé `web_search_url` + ouverture `NSWorkspace.open` |
| Rappel ⌘n | `SlashSuggestion` (texte, détail, icône) | RÉUTILISER, champ `shortcut` |

Dépendances nouvelles : aucune.

## Gate avant tasks
- [x] Chaque élément créé a une recherche d'existant tranchée.
- [x] Aucune duplication évidente non arbitrée.
- [x] Aucun refactor du plan à demander.

## Arbitrages
Aucun.
