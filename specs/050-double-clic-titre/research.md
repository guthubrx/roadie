# Recherche - 050

- TrellisWM 0.9.5 : « Title bar : Double-click frames the window on its own ».
- macOS : réglage « Double-cliquer sur la barre de titre d'une fenêtre pour » (Bureau et Dock),
  préférence globale `AppleActionOnDoubleClick` (`Maximize`, `Fill`, `Minimize`, `None`).
  Sur la machine de l'utilisateur, la clé est absente et `AppleMiniaturizeOnDoubleClick = 0` :
  macOS agrandit la fenêtre.
- Un moniteur global NSEvent observe sans consommer : macOS exécute toujours son action.
  Consommer exigerait une interception permanente (CGEvent tap actif), coûteuse et contraire à
  la session 048. D'où la condition « Ne rien faire ».
- `roadie toggle maximize` existe déjà (`WindowCommandService.toggleMaximize(windowID:)`).
