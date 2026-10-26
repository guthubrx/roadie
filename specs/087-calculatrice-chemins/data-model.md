# Modèle de données 087

- `LauncherCalculation { expression, value: Double, text }` : `text` = résultat mis en forme.
- `LauncherCalculator.evaluate(_:locale:) -> LauncherCalculation?` ; nil si la saisie n'est pas un
  calcul complet et fini.
- `LauncherPathRules.isPath(_:commands:rootEntries:) -> Bool` ; `parts(_:home:) -> LauncherPathQuery`.
- `LauncherPathQuery { directory: String, prefix: String, typedBase: String, exact: String }` :
  `typedBase` garde `~` pour la complétion.
- `LauncherPathListing.list(_ query:) -> [LauncherFile]` (dossiers d'abord, par nom).
- `LauncherList.Row.calc(LauncherCalculation)`, id `calc` ; liste chemin : en-tête « Chemin » + `.file`.
