# Recherche — session 025

Diagnostic local, sans nouvelle bibliothèque :

- La capture fournie confirme la faible taille des explications et le menu vide.
- Le fichier réel contient `split_policy = "balanced"` et `default_strategy = "mutableBsp"`.
- Le catalogue normalise déjà `mutableBsp` en `spatialBsp`, mais omet `balanced`.
- Le moteur sépare une fenêtre en mode `dwindle` et répartit le groupe en deux dans les autres modes.
- Garder `balanced` comme choix distinct évite de réécrire la configuration à l'ouverture.
- Les tags SwiftUI restent les valeurs techniques ; les noms français concernent seulement l'affichage.

## Observation du rendu natif

Le rendu hors écran par `NSHostingView` fonctionne sans capture du bureau.
Inspection des contrôles réels : les champs ont une police de 16 points, mais
`SwiftUIPopupButton` impose 13 points malgré la police de la vue. Un contrôle
`NSPopUpButton` local permettra de définir explicitement la police du bouton et du menu.
Les captures à 1040 et 760 points confirment que les explications ne sont plus comprimées.

## Revue indépendante

La revue ne bloque pas la correction initiale. Retenir : affichage de la valeur brute
non reconnue sans normalisation supplémentaire ; préciser que le découpage s'applique au
mode Arbre automatique ; nommer le champ et le stepper pour l'accessibilité.
Les noms techniques distinguent les deux variantes équilibrées, mais le choix par défaut
sera également nommé pour réduire l'ambiguïté.
