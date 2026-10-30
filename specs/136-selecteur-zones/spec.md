# Session 136 - Zones dans le sélecteur de fenêtres

**Date** : 30 octobre 2026 · **Branche** : `136-selecteur-zones` (sur 135, non fusionnée)

## Besoin

⌥Tab (session 135) a son propre panneau : pas de flèches, pas de souris, comportement différent de ⌘Tab.
L'utilisateur veut exactement le même comportement que le sélecteur de fenêtres, en partageant le code. Il veut
aussi des zones issues des clics ordinaires (plusieurs par fenêtre, nombre réglable) et une durée de conservation.

## Décisions de l'utilisateur

- Conservation : 20 zones au plus et 24 heures, deux valeurs réglables.
- Clics ordinaires : enregistrés comme zones, plusieurs par fenêtre, nombre réglable dans les Paramètres.
- Sélecteur commun : ⌥Tab devient un profil du sélecteur de fenêtres.

## Exigences

- **FR-001** Un profil du sélecteur (`[[switcher.shortcuts]]`) a une source : `windows` (défaut) ou `zones`. Un profil
  `zones` montre les zones récentes avec le comportement complet du sélecteur (présentations, styles, flèches,
  souris, Échap, recherche, relâchement). Paramètres > Sélecteur, éditeur des profils.
- **FR-002** Une zone apparaît comme une carte : sa photo (style vignettes) ou l'icône de son application, son
  texte, son application ; regroupée sous son bureau et sa stage comme une fenêtre. Ordre : l'historique, la plus
  récente d'abord ; si sa fenêtre est au premier plan, la sélection initiale passe à la suivante.
- **FR-003** Valider une zone ramène sa fenêtre (stage et bureau compris) puis clique la zone (session 135). Les
  actions du sélecteur s'appliquent à la fenêtre de la zone.
- **FR-004** Conservation : `[switcher] zone_history_size` (20, 1 à 50), `zone_history_hours` (24, 1 à 168) ; une
  zone qui sort de l'historique perd sa photo.
- **FR-005** Clics ordinaires : un clic gauche dans une fenêtre d'une autre application que Roadie devient une zone
  (élément sous le pointeur ; élément trop grand : un rectangle autour du clic), photo comprise.
  `[switcher] zone_clicks_per_window` (3, 0 à 10 ; 0 coupe) limite les zones gardées par fenêtre.
- **FR-006** Le panneau ⌥Tab de la session 135, son raccourci (`zone_history_hotkey`) et son réglage sont retirés ;
  chez l'utilisateur, un profil « Zones » `alt+tab` les remplace.

## Critères

- **SC-001** ⌥Tab ouvre le sélecteur sur les zones ; ↑↓←→, souris et Échap s'y comportent comme dans ⌘Tab.
- **SC-002** Trois clics ordinaires dans une fenêtre y laissent trois zones ; un quatrième remplace la plus ancienne.
- **SC-003** Une zone de plus de 24 heures n'apparaît plus.
