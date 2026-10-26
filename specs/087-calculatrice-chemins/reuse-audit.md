# Audit de réutilisation 087

Statut : `OK`. Repli manuel (`rg`), 26 octobre 2026.

| Élément | Existant | Issue |
|---|---|---|
| Évaluation d'un calcul | aucun `NSExpression` ni analyseur dans `Sources` (`evaluate(` = règles de fenêtres, maintien de disposition) | CRÉER `LauncherCalculator` (research R1) |
| Lignes de fichier, verbes, ouverture | `LauncherFile`, `Row.file`, `performFile` (077) | RÉUTILISER tels quels pour les chemins |
| Lecture d'un dossier | `contentsOfDirectory` dans `LauncherAppCatalog` (applications, un niveau) | RÉUTILISER le motif, CRÉER `LauncherPathListing` (filtre, génération, plafond) |
| `~` | `expandingTildeInPath` partout | RÉUTILISER |
| Noms des commandes `/` | `SlashCommandCatalog.commands` (noms et alias) | RÉUTILISER |
| Ligne en tête | `LauncherList.prepend` (079) | RÉUTILISER |
| Appariement | `LauncherMatch.score` | RÉUTILISER |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
