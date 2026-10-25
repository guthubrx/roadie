# Recherche 079

## R1 Langues
Roadie n'a pas de système de traduction (aucun `NSLocalizedString`, interface écrite en
français). Les mots de la phrase sont reconnus dans les deux langues à la fois, sans réglage ;
les titres affichés restent en français. Les noms de stages et d'applications sont ceux de
l'utilisateur.

## R2 Analyse
Analyse de la fin vers le début : position, mot de destination, nombre après `bureau`/`écran`,
nom de stage sur un ou deux mots ; arrêt au premier mot inconnu ; le reste cherche l'objet.
Aucun mot reconnu, ou rien avant : pas de phrase. O(m × d), m mots, d destinations.

## R3 Positions
Arbre (spatialBsp) : `insert` refuse ; `WindowCommandService.warp(_:)` déplace la fenêtre active
dans la direction. `toggleMaximize(windowID:)`, `toggleFloating(windowID:)` existent. La position
s'applique après le placement et le focus de la fenêtre.

## R4 Abréviations
Objets durables seulement : application (chemin), fichier (chemin). Destination gardée par nom de
stage réel, `ici` ou `nouvelle` ; résolue à l'usage par `LauncherSearchContext.stage(for:in:)`.
