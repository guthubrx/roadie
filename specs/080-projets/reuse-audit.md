# Audit de réutilisation 080

Statut : `OK`. Repli manuel (`rg`).

| Élément | Existant | Issue |
|---|---|---|
| Projet | « recettes » du lot 4 (non faites) ; `windowBookmarks` (une fenêtre, pas une stage) | CRÉER `StageProjects` |
| Document, adresse | `axDocumentRead` (077) | RÉUTILISER, étendre à l'adresse web |
| Placement | `placeNewWindow` (077) | RÉUTILISER, rendre la fenêtre placée |
| Création de stage | `StageCommandService.createStage(named:…)`, `switchTo` | RÉUTILISER |
| Arbre | `BSPTree`, `setBSPTree` | RÉUTILISER |
| Nouvelle fenêtre d'une application ouverte | `postNewWindowShortcut` (074) | RÉUTILISER |

## Gate avant tasks
- [x] Recherche d'existant tranchée.
- [x] Aucune duplication non arbitrée.
- [x] Aucun refactor à demander.

## Arbitrages
Aucun.
