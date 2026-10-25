# Modèle de données 076

- `LauncherRanking.Entry.contexts: [String: Context]?` ; `Context { anchor: Double,
  abbreviations: [String: Int] }`. Clé : `stage:<nom>` ou `scope:<display>/<desktop>/<stage>`.
  Au plus 6 par objet, au plus 8 abréviations par contexte.
- `LauncherSearchContext.rankingContext: String?`.
- `SlashSuggestion.Icon.window(UInt32, app: String?)` : identifiant de fenêtre et chemin de
  l'application pour la pastille et le repli.
