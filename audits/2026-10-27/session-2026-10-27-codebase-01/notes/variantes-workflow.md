# Recherche de variantes — suppression hors dossier de workflow

Cause : le nom de dossier provient de données externes. Le remplacement de « / » par « - » ne neutralise pas les composants spéciaux « . » et « .. ».

Recherche : `rg -n 'appendingPathComponent\([^)]*(name|id|ID|uid|arg|path|key|scope|file)' Sources/RoadieDaemon Sources/RoadieCore`. Les occurrences pertinentes sont `CLICommandRouter.runWorkflowCommand` (installation et suppression), `AlfredAutomationTasks.task` (lecture, garde séparée contre `..`), `AlfredScriptRunner` et `AlfredWorkflow.icon` (lecture ou exécution de fichiers d'un workflow), et `TargetMacroService` (nom filtré séparément). Les autres occurrences sont des chemins système, des noms fixes ou des entrées de fichier choisies explicitement.

Témoins : l'installation avec `bundleid=".."` et `--replace` peut supprimer le parent ; `bundleid="."` peut supprimer le dossier de tous les workflows. La suppression par nom présente la même faiblesse si un `info.plist` existe dans le dossier visé. Ces chemins sont couverts ensemble par les tests du routeur dans la session 093. La reproduction Swift isolée utilise la même construction et la même opération de suppression ; sa sortie montre la disparition du fichier témoin, uniquement dans le bac à sable.

Limites : aucune archive non fiable n'a été installée sur la configuration réelle. Les liens symboliques et l'extraction des archives nécessitent une analyse distincte.
