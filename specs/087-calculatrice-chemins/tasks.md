# Tâches 087

## US1 Calculatrice (P1)
- [x] T001 Tests puis `LauncherCalculator` (`Sources/RoadieDaemon/LauncherCalculator.swift`) : priorités,
  `^` à droite, moins unaire, `,`/`.`, fonctions après `=`, saisie incomplète et non finie → nil,
  10 000 saisies aléatoires sans plantage (`Tests/RoadieDaemonTests/Spec087CalculatorTests.swift`). FR-001, FR-003.
- [x] T002 Ligne « Calcul » en tête et choisie (`LauncherList.Row.calc`), Retour et ⌘C copient,
  la barre se ferme sur Retour (`TargetOverlayPresenter.swift`). FR-002.
- [x] T007 Maj + chiffre écrit le chiffre dans une saisie vide ou de calcul quand la touche des
  raccourcis est Maj (`SearchInputPanel.swift`) ; test du panneau. FR-009.

## US2 Chemins (P1)
- [x] T003 Tests puis `LauncherPathRules` (`Sources/RoadieDaemon/LauncherPath.swift`) : règle `/`
  (commandes et alias contre éléments de `/`), `~`, découpage dossier/suite, complétion
  (`Tests/RoadieDaemonTests/Spec087PathTests.swift`). FR-004, FR-006.
- [x] T004 `LauncherPathListing` : lecture hors fil principal, génération, filtre, cachés, dossiers
  d'abord, 200 gardés ; test sur un dossier temporaire. FR-005.
- [x] T005 Barre : aiguillage commande/chemin dans `replaceInput` et `handleSearch`, liste « Chemin »
  de lignes `.file`, rien d'autre cherché, Tab complète, → ouvre les verbes. FR-004 à FR-008.

## Livraison
- [x] T006 Suite complète, installation signée, santé, docs FR/EN (`docs/fr|en/features.md`),
  CHANGELOG, index des sessions, `validation.md`.
