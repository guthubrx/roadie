# Recherche — session 025

Diagnostic local, sans nouvelle bibliothèque :

- La capture fournie confirme la faible taille des explications et le menu vide.
- Le fichier réel contient `split_policy = "balanced"` et `default_strategy = "mutableBsp"`.
- Le catalogue normalise déjà `mutableBsp` en `spatialBsp`, mais omet `balanced`.
- Le moteur sépare une fenêtre en mode `dwindle` et répartit le groupe en deux dans les autres modes.
- Garder `balanced` comme choix distinct évite de réécrire la configuration à l'ouverture.
- Les tags SwiftUI restent les valeurs techniques ; les noms français concernent seulement l'affichage.
