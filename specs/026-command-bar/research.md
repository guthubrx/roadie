# Diagnostic et réutilisation — session 026

- SearchBarLayout calcule la largeur avec `contentWidth + 40`, donc une saisie
  ou une suggestion longue déplace le bord gauche. L'ancrage vertical est déjà stable.
- drawSearchBar concatène emoji de loupe, saisie et texte du compteur dans une
  même ligne, dessinée en police monospace ; les deux contours verts font 1,5 point.
- SearchKeyInput distingue déjà Tab, flèches et touches Control. En recherche,
  la session ignore cette distinction et appelle toujours `next()`.
- SlashCommandModel.complete complète déjà commandes et arguments, mais avance
  la sélection avant insertion même si l'utilisateur a choisi une proposition.
- Les tailles searchTextFontSize et commandTextFontSize existent et sont mises
  à jour en place depuis la session 025. Aucun nouveau paramètre nécessaire.
- Tests et rendus hors écran existants réutilisables. Police système native :
  aucune installation de police ni dépendance nécessaire.
- Revue indépendante de cette session explicitement autorisée par l'utilisateur.
