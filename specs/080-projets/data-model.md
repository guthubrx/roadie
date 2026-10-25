# Modèle de données 080

- `ProjectWindow { bundleID, appPath, document: String?, url: String?, title }`.
- `StageProject { name, savedAt, windows: [ProjectWindow], tree: BSPTree? }` ; feuilles de
  `tree` = `WindowID(rang)`, rangs à partir de 1.
- `StageProjectBook { projects: [String: StageProject] }` (clé : nom replié), fichier
  `~/.roadies/projects.json`.
- `LauncherList.Row.project(StageProject)`, `LauncherSubject.project(String)`,
  `LauncherVerb.saveProject`, `.reopenProject`, `.deleteProject`.
