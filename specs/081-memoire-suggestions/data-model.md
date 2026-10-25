# Modèle de données 081

- `WindowMove { windowID, bundleID, appName, from: StageScope?, to: StageScope, at }`.
- `LauncherMemoryBook { moves: [WindowMove] (≤ 200), declined: [String: Date] }` ; clé de refus
  `bundle|stage-context` ; `Date.distantFuture` = jamais, sinon « plus tard » jusqu'à cette date.
  Fichier `~/.roadies/launcher-moves.json`.
- `RuleSuggestion { bundleID, appName, stage: StageScope, stageTitle, context, count }`.
- `LauncherList.Row.action(key, LauncherAction, title, detail)`, `.rule(RuleSuggestion, RuleChoice)`.
- `TargetSearchBar.chip`, `SearchKeyInput.Kind.showRules` (⌘R).
