# Session 133 - Recherche à l'écran séparée du lanceur

**Date** : 30 octobre 2026 · **Branche** : `133-recherche-ecran` (sur 132 et 131, non fusionnées)

## Besoin (30 octobre 2026)

La barre est née comme une recherche à l'écran (SPEC-021, à la manière de Homerow) : on tape, les éléments
visibles qui correspondent reçoivent une étiquette verte, Retour clique. Depuis la session 073, la même saisie
alimente le lanceur, dont la liste s'affiche au-dessus de la barre et masque ce que l'on cherche à l'écran.
L'utilisateur lance le lanceur par ⌘Espace (`search_hotkey`) et ne veut pas que cela change ; Capslock + F
(⌘⌃⌥F) ne fait plus rien et doit ouvrir la recherche à l'écran.

## Exigences

- **FR-001** Un raccourci global `screen_search_hotkey` (`[experimental.target_mode]`) ouvre la barre en
  mode « à l'écran » ; vide par défaut (le défaut de `search_hotkey` est déjà ⌘⌃⌥F), réglé à
  `command+control+alt+f` chez l'utilisateur. Paramètres > Raccourcis.
- **FR-002** En mode « à l'écran », aucune liste : la barre ne montre que la saisie et le nombre de
  correspondances ; les correspondances portent leur étiquette verte à l'écran, la cible choisie est
  encadrée (rendu d'avant la session 073). ↑/↓ changent de cible, Maj + étiquette la choisit, Retour clique
  (Maj = clic droit, ⌘ = ⌘-clic, double Retour = double-clic), `/` garde le mode commande.
- **FR-003** Le lanceur (`search_hotkey`, `roadie targets search`) ne change pas.
- **FR-004** `roadie targets screen` ouvre le même mode.

## Critères de réussite

- **SC-001** Capslock + F ouvre une barre sans liste ; taper un mot visible à l'écran le montre étiqueté.
- **SC-002** ⌘Espace ouvre toujours le lanceur avec sa liste.
