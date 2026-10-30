# Validation - Session 132

**Date** : 30 octobre 2026

## Tests

- `scripts/test --no-parallel` : 2 326 tests dans 345 suites réussis (103,7 s).
- Deux tests ajustés à des changements voulus : `TargetSearch028DismissalTests` (la barre écoute la molette en
  recherche depuis la session 131) et `SettingsViewModelTests` (la catégorie Règles a un interrupteur).

## Essai réel (Roadie installé, PID 72774, santé 5/5, signature roadied-cert)

Fenêtres d'informations du Finder ouvertes par AppleScript sur `/tmp/roadie-crash-lab/essai info.txt` :

1. Ouverture à x = 10 (sous le rail) : `floating.placed` raison `rail`, cadre 158,10 ; relu à x = 158.
2. Après `remember_frame = true` sur la règle `finder-get-info` : déplacement de la fenêtre, place retenue
   `{"finder-get-info": {"x": 630, "y": 216, "width": 400, "height": 887}}`.
3. Fermeture puis réouverture : `floating.placed` raison `remembered`, relu à x = 630, y = 216.

## Limites

- Le Finder impose la largeur (400) de ses fenêtres d'informations et les agrandit en hauteur après
  l'ouverture : pour elles, seule la position tient. Un changement fait par l'application elle-même après
  l'ouverture est retenu comme un déplacement : la fenêtre revient alors à la taille choisie par l'application.
- Les fenêtres ne sont ni rattachées à une stage ni dotées du menu de barre de titre (hors périmètre).
- Preuves visuelles : aucun diaporama, les clics simulés sont refusés sur ce poste ; essai fait par
  AppleScript et relevés de Roadie.

## Configuration de l'utilisateur

Sauvegardée dans `~/.config/roadies/roadies.toml.bak-132-*`, puis `remember_frame = true` ajouté à la règle
`finder-get-info` et à la ligne Thunderbird « # Reminder », comme demandé.
