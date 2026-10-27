# Plan 099

## Recherche
- R1 Touche : `TargetSearchHotkey.resolve` (disposition active) donne code et modificateurs Carbon ;
  converti en `NSEvent.ModifierFlags` à l'ouverture de la barre ; `SearchInputPanel.navigation` la
  reconnaît avant les autres touches (`.cycleView`). Défaut ⌘G : libre dans la barre (⌘ A C X V Z W Y
  S R pris).
- R2 Chip : la pastille du compteur existe (`TargetSearchBar.counterText`) ; le chip y entre en tête ;
  `SearchBarRenderer.counterFrame` rend son rectangle pour le clic (même calcul que le dessin).
- R3 Rendu : la grille de la 092 (`SearchGrid`, `makeGrid`, `drawTile`, ← →, voisins) sert telle quelle ;
  les lignes passent par `.idle(rows)` sans titres de section.
- R4 Vignette : `CGImageSourceCreateThumbnailAtIndex` (512 px) au lieu de l'image entière : une photo de
  20 Mo ne se charge pas en entier pour une tuile.
- R5 Mémoire : fichier JSON simple comme l'historique (090) ; écrit au changement seulement.

## Fichiers
`Sources/RoadieCore/Config.swift` (réglage), `SettingsCatalog.swift`, `SettingsView.swift`,
`LauncherViews.swift` (nouveau : présentation, source, mémoire, lignes), `LauncherSearchContext.swift`,
`TargetModeRuntimeController.swift`, `TargetOverlayPresenter.swift`, `SearchInputPanel.swift`,
`SearchBarRenderer.swift`, `Tests/RoadieDaemonTests/Spec099ViewModeTests.swift`.

## Constitution
XVIII : sources et filtrage O(n) ; cycle O(1) ; mémoire O(s log s) à l'écriture seulement.
XIX : un seul type nouveau (présentation + mémoire) ; grille, voisins, enregistreur, compteur réutilisés.
