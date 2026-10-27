# Audit de l'existant 092

Statut : **OK** (aucun doublon évident, deux arbitrages écrits).

| Élément du plan | Existant trouvé | Décision |
|---|---|---|
| Lecture du JSON des tuiles | `AlfredScriptFilterResponse.parse` (`AlfredScriptFilterResponse.swift:42`) | RÉUTILISER, ajout de `preselect` |
| Filtre de la saisie | `AlfredScriptFilterResponse.filter` mode 2 (`:113`) | RÉUTILISER |
| Script de source | `AlfredScriptRunner.run` type 8 (`AlfredScriptRunner.swift:97`) | RÉUTILISER |
| Lignes et Retour | `.workflowItem`, `confirmWorkflow`, `finishWorkflow` (`TargetOverlayPresenter.swift:1483`) | RÉUTILISER |
| Icônes des tuiles | `workflowIcon` (`TargetOverlayPresenter.swift:1554`), `SearchBarRenderer.icon` | RÉUTILISER |
| Barre rouverte par un workflow | `showBar` / `reopenSearch` (`TargetModeRuntimeController.swift:754`) | ÉTENDRE (vue en attente) |
| Déclencheur externe | `AlfredWorkflowEngine.externalTrigger` (`AlfredWorkflowEngine.swift:71`) | ÉTENDRE (`externalid`) |
| Sortie `config` | `AlfredRunScriptOutput.parse` (`AlfredScriptFilterResponse.swift:140`) | RÉUTILISER, appliquée par le moteur |
| Disposition en tuiles | `WindowSwitcherGrid.layout` (`WindowSwitcherPanel.swift:56`) | CRÉER `SearchBarLayout.makeGrid` (arbitrage A1) |
| Navigation 2D | `SwitcherNavigation.destination` (`WindowSwitcherInteraction.swift:8`) | CRÉER calcul par rang (arbitrage A2) |
| Vue de grille | aucun équivalent (`rg "userinterface"` : seulement la fiche) | CRÉER `AlfredGridView` (donnée) |

## Arbitrages
- **A1** `WindowSwitcherGrid.layout` dépend de `WindowSwitcherAppearance` (styles, vignettes 16:9) et
  d'une origine en haut dans une vue défilante ; la barre est en bas d'écran, origine en bas, et
  partage `suggestionRows`/`firstVisible` entre dessin et clic. Une fonction de ~25 lignes dans
  `SearchBarLayout` évite d'adapter l'apparence du sélecteur. Duplication légère assumée.
- **A2** `SwitcherNavigation.destination` parcourt toutes les cartes (O(n)) pour des cartes de tailles
  différentes ; la grille est régulière : rang ± 1 ou ± colonnes en O(1), espaceurs sautés.

## Dépendances
Aucune nouvelle.

## Gate avant tasks
- [x] Chaque élément du plan a une décision.
- [x] Les créations ont une justification écrite.
- [x] Aucune dépendance externe ajoutée.
