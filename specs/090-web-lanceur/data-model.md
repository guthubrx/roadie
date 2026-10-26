# Modèle de données 090

- `WebSearch { keyword, title, url }` (RoadieCore, `Codable`) ; `TargetModeConfig.webSearches:
  [WebSearch]?` (nil = défauts), `fallbackSearches: [String]` (mots-clés).
- `LauncherWebRow { kind (.address(URL) | .search(title, URL) | .hint(WebSearch)), title }`.
- `LauncherSubject.url(URL)` ; verbes `.open`, `.openIn`, `.bringHere`, `.copyPath` (« Copier l'adresse »).
- `LauncherHistoryBook { entries: [{query, at}] }`, 20 au plus ; `LauncherHistoryStore`.
- `LauncherList.Row.web(LauncherWebRow)`, `.history(String)`.
