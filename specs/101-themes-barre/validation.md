# Validation 101

- Tests ajoutés : `Tests/RoadieDaemonTests/Spec101ThemeTests.swift` (6 tests) : thème par défaut,
  tailles des thèmes d'Alfred, mode sombre, lecture d'un thème exporté et d'un thème d'Alfred,
  nombre de résultats, rendu différent de chaque thème fourni.
- Rendus hors écran des dix thèmes relus (`ROADIE_THEME_PREVIEW_DIR`) : couleurs, polices et
  sélection conformes aux thèmes d'Alfred.
- Flou derrière la barre : posé par `NSVisualEffectView` ; non vérifiable en test, à voir à l'écran.
