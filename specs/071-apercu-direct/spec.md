# Session 071 - Aperçu en direct des déplacements, création dans le vide, centrage

Demande du 25 octobre 2026. Choix validés : glissement doux (0,15 s), fantôme à la
future place seul (rien ne suit le pointeur), centrage vertical, création d'un contenant
en déposant dans le vide ; s'applique aussi entre écrans.

## Comportement
- Une intention de dépôt (`OverviewDropIntent`) décrit le résultat ; le modèle d'aperçu
  (`OverviewModel.previewing`) est recomposé à chaque nouvelle place et affiché en
  glissement doux. L'élément déplacé est dessiné en fantôme (alpha 0,45).
- Les places visées se calculent sur la disposition figée au début du geste.
- Fenêtre lâchée dans la zone vide d'un bureau : nouvelle stage (numéro suivant, en
  dernier). Fenêtre ou stage lâchée sous le dernier bureau d'un écran : nouveau bureau
  (premier numéro libre après le dernier montré, bureau vide réutilisé).
- Après le dépôt, l'aperçu reste affiché jusqu'au rechargement ; un refus le retire en
  douceur.
- La composition est centrée en hauteur.
