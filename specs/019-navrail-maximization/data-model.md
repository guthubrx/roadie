# Modèle de données

LayoutIntent existant conserve scope, windowIDs, placements, source et zoomedWindowID.

- zoomReservesRail : Bool optionnel ; true = maximisation suivant la visibilité du rail ; absent/false = plein écran Roadie.
- restorePlacements : dictionnaire optionnel WindowID -> Rect ; disposition avant le premier zoom. Conservé à travers les changements de mode.

Transitions : normal -> réservé ou plein écran ; réservé <-> plein écran sans empiler de sauvegardes ; même mode -> normal ; focus sur une voisine -> normal.

Contraintes : fenêtre zoomée présente et cadre accepté ; scope unique ; valeurs positives ; aucun cadre masqué utilisé comme sauvegarde normale. Les anciens JSON décodent les deux nouveaux champs à nil.

Réutilisation : visibleWidths par display et isPinned du store de rail existant ; aucune nouvelle donnée persistée. Le mode reste true même quand la cible temporaire est le plein cadre utile.


Correction placement : RestoreSafetyRunMarker existant ajoute shutdownRequestedAt optionnel ; ancien fichier = nil, crash inchangé. Une demande d’arrêt ne vaut pas restauration complète : cleanExitAt reste absent si failed>0, donc reprise conservée. WrittenFrame existant porte axResultCodes et nativeFullscreenReading optionnels et éphémères, sans nouvelle persistance ni données de titre/application. Le diagnostic de restauration indique seulement les IDs refusés et le nombre de natifs préservés.
