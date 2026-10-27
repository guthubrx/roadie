# Session 102 - Barre déplaçable et place retenue

## Demande

« Pouvoir déplacer l'omnibox et que ce soit persisté. »

## Référence relevée

Alfred : option « saveposition » (la fenêtre déplacée garde sa place), grille de position par défaut,
écran par défaut, écran de la souris ou écran actif (Appearance > Options).

## Exigences

- FR-001 : on glisse la barre par son bord (hors du champ de saisie) ou par le fond de la liste ; elle
  suit le pointeur, la liste aussi.
- FR-002 : au relâchement, la place est retenue (`~/.roadies/launcher-position.json`), en fractions de
  l'écran : la même place relative sur un autre écran. `bar_save_position = false` : rien n'est retenu.
- FR-003 : un double-clic sur le bord oublie la place retenue et remet la place par défaut.
- FR-004 : `bar_position` : `bottom` (historique, liste au-dessus), `center` ou `top` (liste dessous, comme
  Alfred). Une barre retenue dans la moitié haute ouvre sa liste dessous.
- FR-005 : `bar_screen` : écran de la souris (défaut), de la fenêtre active, ou principal.
- FR-006 : la barre et la liste restent entièrement dans l'écran.
- FR-007 : réglages dans Paramètres > Recherche.

## Limites

La barre se déplace dans son écran ; elle ne passe pas sur un autre écran pendant le glisser.
