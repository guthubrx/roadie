# Plan — session 025

## Diagnostic et réutilisation

La capture utilisateur montre des descriptions trop petites et un menu vide.
`SettingsView` impose `.caption` et `.caption2` et partage une ligne entre descriptions et contrôles.
La configuration réelle contient `balanced`, absent des choix du catalogue.
`BSPLayoutStrategy` traite `balanced` et `largest_dim` de la même manière : seul `dwindle` est distingué.

Réutiliser `SettingDescriptor`, `SettingsViewModel`, `SettingsService`, les bindings existants
et `SettingsWindowController.centeredFrame`. Conserver les tags des menus, la validation
et les opérations d'écriture. Ajouter uniquement une traduction de présentation pour les deux menus.

Le rendu natif a montré que les menus SwiftUI restent à 13 points. Utiliser un
`NSPopUpButton` local avec police explicite de 16 points, binding vers le modèle existant,
état désactivé conservé et libellé d'accessibilité. Conserver aussi la valeur brute courante
si elle n'est pas dans les choix, sans permettre de l'écrire comme choix valide.

## Implémentation

1. Ajouter `balanced` et les libellés français dans le catalogue ; couvrir lecture/écriture par tests.
2. Agrandir les polices et les contrôles ; séparer explications et saisie. Fenêtre initiale 1040 × 760.
3. Compiler, exécuter les tests concernés puis la suite Swift, installer et contrôler la santé du daemon.

## Gates

Session validée et worktree isolé. Constitution et standards de tests chargés.
Aucune dépendance ni changement d'algorithme. Traduction des choix en O(1).
La capture native est indisponible : ne pas présenter une compilation comme une validation visuelle.

## Périmètre révisé et validé par l'utilisateur

Les tailles fixes deviennent des paramètres indépendants pour toute l'interface.
Réutiliser les clés existantes du rail, des lettres et de la grille. Ajouter trois tailles
pour la fenêtre des paramètres dans `[interface]`, et trois tailles de recherche/commandes
dans `[experimental.target_mode]`. Les curseurs et les valeurs valides saisies appliquent
les changements immédiatement. Le cache du modèle charge les polices dans chaque catégorie.
Les sessions actives reçoivent leur nouveau style. Le rail reçoit une notification locale
après une écriture réussie ; le watcher du fichier reste actif pour les modifications externes.
La géométrie doit suivre les tailles, sans couper les cartes ou les lignes de commande.

Répartition validée : configuration et overlays ; rail et cartes ; paramètres et intégration.
Revue indépendante après stabilisation commune, puis tests, rendu hors écran et installation.
