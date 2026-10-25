# Modèle de données 079

- `LauncherPosition` : `left`, `right`, `full`, `float`.
- `LauncherPhrase { objectQuery, destination: LauncherDestination?, here: Bool, position }`.
- `LauncherAlias { path, isApp, name, verb, stage: String?, here, newStage, position }` ;
  `LauncherAliasBook { aliases: [String: LauncherAlias] }` dans `~/.roadies/launcher-aliases.json`.
- `LauncherList.Row.phrase(LauncherAction, String)`, `.alias(String, LauncherAction, String)`.
- `SearchKeyInput.Kind.save` (⌘S) ; étape `saving(LauncherAction)`.
