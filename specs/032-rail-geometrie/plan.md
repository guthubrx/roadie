# Plan

1. Réutiliser RailSettings, le catalogue et RailVisualConfig pour `fx.rail.stages.slot_height`.
   Zéro garde la hauteur automatique. Une hauteur explicite reste identique pour tous
   les stages en mode aperçu. Les marges verticales explicites remplacent le retrait
   interne arbitraire de 60 points quand une hauteur est demandée.
2. Réserver un éventail commun pour les cinq aperçus maximum. Borner son décalage
   horizontal à la largeur du rail. Le nombre de fenêtres ne déplace plus l'avant.
   Réutiliser exactement les mêmes cadres dans le dessin et le test du clic.
3. Dans RailPanel, calculer une seule cible de réorganisation pour le repère et le dépôt.
   Afficher le repère dans RailStackView. Nettoyer au lâcher, à l'annulation et à l'arrêt.
4. Reporter les rafraîchissements structurels pendant le glisser droit. Capturer le point
   souris à réception dans le moniteur global. Journaliser une seule fois au dépôt.
5. Tester sur des panneaux AppKit et le store, puis livrer dans la copie combinée
   existante pour préserver le travail parallèle. Installer une hauteur de 120 points,
   vérifier les captures et adapter seulement si le rendu empirique l'exige.

Complexité : géométrie par carte O(1), nombre de couches borné à cinq ; calcul de dépôt
O(n + c), n stages persistés et c cartes représentées. Aucun scan AX par mouvement.
Pas de nouveau contrôleur ou de dépendance. Aucun changement de numéro ou de nom.

## Recherche effectuée

Le maintien de places vides existe dans Waybar (persistent-workspaces), HyprPanel
(bureaux configurés et états available/occupied/active) et Polybar (label-empty).
L'utilisateur préfère ce modèle stable à une suppression des cartes vides.

- https://github.com/Alexays/Waybar/wiki/Module:-Hyprland
- https://github.com/Jas-SinghFSU/HyprPanel/blob/master/src/configuration/modules/config/bar/workspaces/index.ts
- https://github.com/polybar/polybar/wiki/Module:-xworkspaces
