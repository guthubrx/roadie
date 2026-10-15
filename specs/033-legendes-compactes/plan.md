# Plan

- Réutiliser StageCardView, RailStageLabelConfig, RailSettings et le catalogue existants.
- Ajouter écart, perspective et taille de légende distincte. Le cadre de légende est
  dérivé des cadres transformés des aperçus ; le dessin, les limites et la mesure utilisent
  la même géométrie. Conserver la visibilité temporaire existante.
- Dimensionner le bloc aperçu + légende dans l'emplacement pour permettre une hauteur
  réduite sans collision. Les places vides gardent la même hauteur.
- Reproduire le dépôt Outlook/T3/Teams par un test du chemin aperçu → commande → cycle
  suivant. Identifier la première divergence entre arbre annoncé et arbre appliqué.
- Appliquer la correction ciblée au propriétaire du défaut ; pas de nouveau moteur.
- Réutiliser la copie de livraison combinée actuelle. Archiver le patch et ses empreintes.
- Vérifier les suites, installer signé, régler les légendes, redémarrer et capturer les rails.

## Diagnostic reproduit

L'arbre persistant de l'incident contient T3 et Teams ; Outlook est vivant et membre
du même groupe, mais absent de l'arbre. Un ancien signal de destruction en attente
reproduit exactement cette anomalie et le retour au bas gauche, avec changed=true.
Le test sans signal applique correctement le dépôt. Le journal historique ne donne
pas l'identifiant de chaque notification AX détruite ; l'origine du signal historique
reste une déduction étayée par l'état et la reproduction, pas une notification tracée.

Correction ciblée : après vérification de la présence de la fenêtre, un placement
explicite révoque uniquement son signal de destruction antérieur à la commande.
Une fermeture plus récente reste prioritaire ; les fermetures des autres fenêtres
ne sont pas modifiées. La rétractation du signal est journalisée.

## Géométrie des légendes

Taille de légende distincte, 0 hérite de la taille des détails. Le contour projeté
de la première vignette définit l'alignement et l'écart. La perspective du texte
utilise la même projection affine que l'aperçu. Le bloc réserve la hauteur du texte,
son écart et une marge bornée pour les couches. Les mesures de police sont prises
une seule fois à la création de la carte, pas à chaque test de clic.
