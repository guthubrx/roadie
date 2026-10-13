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


## Correction de visibilité — 2026-10-13

- [x] T012 Actualiser la spec, plan, modèle et audit de réutilisation : masqué = plein cadre, visible/pin = réservation, aucune nouvelle persistance.
- [x] T013 Adapter les tests dans Tests/RoadieDaemonTests/PowerUserDesktopCommandTests.swift et PowerUserFocusCommandTests.swift : hidden/pin/hover, resize/overlay, quatre moteurs, origine négative, autres scopes, sauvegarde et priorité native.
- [x] T014 Étendre Sources/RoadieDaemon/DaemonSnapshot.swift et RailController.swift : cible basée sur visibilité et callback overlay ciblé ; empêcher la boucle hide_on_maximized.
- [x] T015 Mettre les six README/guides CLI anglais/français et le guide de test de la spec en cohérence.
- [x] T016 Exécuter la suite Swift complète, relire les changements et vérifier la convergence.


## Correction des placements — 2026-10-13

- [x] T017 Confirmer les causes dans les données depuis 5 h 50 et actualiser spec/plan/reuse-audit ; résultat observable : lien de chaque anomalie au chemin existant et hypothèses restantes nommées.
- [x] T018 Ajouter les reproductions avant correction dans Tests/RoadieDaemonTests/LayoutMaintainerTests.swift puis corriger Sources/RoadieDaemon/LayoutMaintainer.swift : filtre du resize dans son chemin dédié sans supprimer les signaux d’adoption/dérive, stage inactive jamais resize manuel, activation d’une voisine visible ou cachée avant masque, zoom et vraie action de focus conservés (FR-010,011).
- [x] T019 Reproduire les refus transitoires/natifs et corriger le point identifié d’application AX existant ; vérifier reprise bornée, refus explicite et budget conservé (FR-012).
- [x] T020 Ajouter les scénarios restart/crash avant correction dans Tests/RoadieDaemonTests/RestoreSafetyServiceTests.swift puis corriger Sources/RoadieDaemon/RestoreSafetyService.swift et le chemin lifecycle existant si nécessaire : visibilité réelle, garde native et diagnostics fidèles ; fixture native, visible, parkée et refus réel (FR-013).
- [x] T021 Actualiser guide de vérification et mémoire de session, lancer tests ciblés puis suite Swift complète, revue, analyse et convergence exigence par exigence (FR-010 à013, SC-004).


## Convergence

- [x] T022 Vérifier deux passes après un focus AX absent avec repli mémorisé dans une stage zoomée, puis exiger un focus système réel pour quitter le zoom au profit d’une voisine visible ou cachée ; garder CmdTab caché au polling avec preuve de focus réel (FR-011). Rejouer la suite complète et la revue avant livraison.
