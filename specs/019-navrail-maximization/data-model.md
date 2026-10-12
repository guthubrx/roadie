# Modèle de données

LayoutIntent existant conserve scope, windowIDs, placements, source et zoomedWindowID.

- zoomReservesRail : Bool optionnel ; true = maximisation réservée ; absent/false = plein écran Roadie.
- restorePlacements : dictionnaire optionnel WindowID -> Rect ; disposition avant le premier zoom. Conservé à travers les changements de mode.

Transitions : normal -> réservé ou plein écran ; réservé <-> plein écran sans empiler de sauvegardes ; même mode -> normal ; focus sur une voisine -> normal.

Contraintes : fenêtre zoomée présente et cadre accepté ; scope unique ; valeurs positives ; aucun cadre masqué utilisé comme sauvegarde normale. Les anciens JSON décodent les deux nouveaux champs à nil.
