# Session 032 — Géométrie et dépôt du navrail

## Fiche Synthèse

Spec: 032-rail-geometrie
Titre: Alignement, hauteur des emplacements et dépôt précis
Statut: In Progress
Priorité: P1
Tâches: 3/4 (75%)
Tests: 1544/1544 (100%)

Validation utilisateur : « corrige », le 2026-10-15, après diagnostic et comparaison.

## Besoin et preuves

- La vignette avant est décalée selon le nombre de fenêtres : cinq fenêtres
  ajoutent 40,8 points de compensation horizontale avec la configuration actuelle.
- Une case de 184 points contient un aperçu de 78 points. Deux aperçus consécutifs
  sont séparés d'environ 119 points avant perspective, malgré un gap de 13 points.
- L'utilisateur conserve les places des stages nommés vides pour lire les rangs.
  Il refuse leur suppression ou leur compression conditionnelle à l'occupation.
- Le point du lâcher historique n'est pas journalisé. Les captures confirment un
  grand écart ; elles ne prouvent pas à elles seules un mauvais ordre de dépôt.

## Critères d'acceptation

1. Aligner horizontalement les vignettes avant indépendamment du nombre de fenêtres,
   avec dessin et zones de clic cohérents, sans faire déborder la pile du rail.
2. Proposer une hauteur d'emplacement réglable, commune aux cartes vides et occupées.
   Zéro conserve le calcul automatique existant. Réduire la hauteur sur l'installation
   courante sans changer la taille de police ni supprimer les groupes vides.
3. Conserver l'écart entre cases comme réglage distinct, avec un libellé clair.
4. Montrer la position d'insertion pendant un glisser de stage. Le dépôt doit suivre
   la même géométrie. Garder les places nommées, même lorsque leurs traits sont masqués.
5. Stabiliser le rail pendant le geste et relever les coordonnées avant report asynchrone.
6. Préserver les groupes, les numéros temporaires, le tiling et les corrections déjà installées.

## Validation

Tests du rendu et du clic pour 1 à 5 fenêtres, hauteur constante, police lisible,
configuration, slots vides, dépôt vers le haut et le bas et indicateur. Suite combinée,
installation signée, redémarrage et captures ciblées des deux rails.
