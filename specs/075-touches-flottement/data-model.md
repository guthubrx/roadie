# Modèle de données 075

- `LauncherModifier` : `command`, `option`, `control`.
- `LauncherVariant` : `title` (texte annoncé), `effect` : `.action(LauncherAction)` ou
  `.webSearch(String)`. Calculé, jamais stocké.
- `SearchKeyInput.Kind` : `confirm(shift, command, option, control, isRepeat)`, `pick(Int)`
  (1 à 9), `actions` (→ en fin de saisie).
- `SlashSuggestion.shortcut: String` : rappel affiché à droite (« ⌘3 »), vide par défaut.
- Règle générée `affinity-app-<bundle>` (`roadies.generated.toml`) : `assign_*` (affinité) et
  `floating = true` ou `manage = true` (tuilage durable), indépendants.
- Config `[experimental.target_mode]` : `actions_hotkey` (défaut `cmd+ctrl+opt+shift+f`),
  `web_search_url` (défaut `https://www.google.com/search?q={query}`).
