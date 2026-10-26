# Modèle de données 091

- `LauncherSelection { subjects: [LauncherSubject] }` : ordre d'ajout, unicité par `rankingKey`
  (fenêtre : son identifiant) ; `toggle`, `add`, `removeLast`, `clear`, `contains`.
- `LauncherSelectionVerb` : `.sendTo`, `.bringHere`, `.close`, `.minimize`, `.quit`, `.hide`,
  `.copyPaths`, `.reveal`, avec `count(in:)` et `actions(destination:) -> [LauncherAction]`.
- `SearchKeyInput.Kind` : `.selectToggle`, `.selectAddNext`, `.selectRemoveLast`, `.selectionVerbs`,
  `.selectClear`.
- `WindowMove.batch: String?`.
