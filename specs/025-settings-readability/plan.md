# Plan — session 025

## Diagnostic et réutilisation

La capture utilisateur montre des descriptions trop petites et un menu vide.
`SettingsView` impose `.caption` et `.caption2` et partage une ligne entre descriptions et contrôles.
La configuration réelle contient `balanced`, absent des choix du catalogue.
`BSPLayoutStrategy` traite `balanced` et `largest_dim` de la même manière : seul `dwindle` est distingué.

Réutiliser `SettingDescriptor`, `SettingsViewModel`, `SettingsService`, les bindings existants
et `SettingsWindowController.centeredFrame`. Conserver les tags des menus, la validation
et les opérations d'écriture. Ajouter uniquement une traduction de présentation pour les deux menus.

## Implémentation

1. Ajouter `balanced` et les libellés français dans le catalogue ; couvrir lecture/écriture par tests.
2. Agrandir les polices et les contrôles ; séparer explications et saisie. Fenêtre initiale 1040 × 760.
3. Compiler, exécuter les tests concernés puis la suite Swift, installer et contrôler la santé du daemon.

## Gates

Session validée et worktree isolé. Constitution et standards de tests chargés.
Aucune dépendance ni changement d'algorithme. Traduction des choix en O(1).
La capture native est indisponible : ne pas présenter une compilation comme une validation visuelle.
