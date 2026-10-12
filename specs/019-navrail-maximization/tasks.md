# Tâches — Maximisation réservée

## Préparation

- [x] T001 Vérifier le gate de réutilisation et la checklist dans specs/019-navrail-maximization ; résultat : PASS, pas de clarification.

## US1 — Bascule et restauration (P1)

- [x] T002 Ajouter avant implémentation des tests de bascule, restauration, transitions et anciens JSON dans Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift ; vérifier cadres et sauvegarde unique.
- [x] T003 Étendre Sources/RoadieDaemon/LayoutIntentStore.swift et WindowCommands.swift : mode réservé, sauvegarde, bascule commune, refus avant masquage (FR-001,004,005,007,009).

## US2 — Cadre et maintien (P1)

- [x] T004 Ajouter les tests auto-hide resize/overlay/pin, coordonnées négatives, changement de largeur et refus dans Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift et LayoutMaintainerTests.swift (FR-002,003,006,007).
- [x] T005 Ajouter le cadre partagé dans Sources/RoadieDaemon/DaemonSnapshot.swift, actualiser plans et restauration d'intent (FR-002,003,006).
- [x] T006 Adapter Sources/RoadieDaemon/LayoutMaintainer.swift et StageCommands.swift : cible réservée au maintien, focus et retour de stage ; vérifier l'isolation des autres scopes (FR-004,006,009).

## US3 — Accès et documentation (P2)

- [x] T007 Ajouter la route/aide dans Sources/RoadieDaemon/CLICommandRouter.swift et vérifier Tests/RoadieDaemonTests/CLICommandRouterTests.swift (FR-008).
- [x] T008 Ajouter l'action ciblée dans Sources/RoadieDaemon/TitlebarContextMenuController.swift et WindowContextActions.swift ; tester dans Tests/RoadieDaemonTests/TitlebarContextMenuTests.swift (FR-008).
- [x] T009 Actualiser README.md, README.fr.md, docs/en/README.md, docs/fr/README.md, docs/en/cli.md et docs/fr/cli.md ; vérifier les trois commandes distinctes (FR-008).

## Vérification

- [x] T010 Exécuter ./scripts/with-xcode swift test ; suite complète verte, preuves durables (SC-001 à SC-004).
- [x] T011 Faire la self-review XIX/XX ; vérifier code/spec/tests, puis convergence sans modification de tasks.md et audit v14 restreint.

Toutes les tâches d'implémentation doivent être cochées avant le commit. La livraison et le nettoyage sont prouvés séparément dans le dossier durable de livraison ; ils ne constituent pas des tâches de code.

Dépendances : T001 -> tests T002/T004 -> T003/T005/T006 -> T007/T008/T009 -> T010 -> T011. Les chemins sont relatifs à la racine du worktree. Les tests utilisent les fixtures et la suite existantes.
