# Modèle de données 077

- `LauncherFile { path, name, isFolder, lastUsed }`, `rankingKey = "file:<path>"`.
- `LauncherList.Row.file(LauncherFile)`, `Section.files` (5 lignes).
- `LauncherSubject.file(LauncherFile)` ; `LauncherVerb.reveal`, `.quickLook`, `.copyPath`.
- Classement : clé `folder:<dossier>`, contextes = stages où ses fichiers ont été ouverts.
- `SearchKeyInput.Kind.copy`, `.preview`.
- Commande `launcher.launch` : `path`, `stage`, `newStage`.
