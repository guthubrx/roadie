# Tâches — Session 143

## Cadrage
- [x] T001 Définir exigences, contrats, réutilisation et annulation dans specs/143-glisser-direct/.
## US2 — Choix utilisateur
- [x] T002 [US2] Ajouter TilingConfig.liveDragPreview, clé validée, descripteur FR/EN et application sans retuilage ; tests dans Tests/RoadieDaemonTests/Spec143LiveDragTests.swift.
## US1 / US3 — Aperçu réversible
- [x] T003 [US1] Brancher les places figées de Sources/RoadieDaemon/DropPreviewController.swift sur InteractiveFrameDispatcher ; exclure source, coalescer et restaurer les voisines.
- [x] T004 [US3] Clôture bornée avant dépôt et annulation Échap/contexte dans DropPreviewController.swift et RailController.swift ; garder les commandes finales existantes.
## Vérification et installation
- [ ] T005 Tests ciblés puis suite, revue indépendante, documentation FR/EN et preuves natives dans preuves-corrections/2026-10-31-143-glisser-direct/preuves.html.
- [x] T006 Build Release, installation signée, santé et reçu dans specs/143-glisser-direct/validation.md ; aucun bump ni publication de release.

Dépendances : T001 → T002 → T003 → T004 → T005 → T006. Un responsable, pas de délégation de code. Réglage testable indépendamment. Géométrie et restauration partagent le même propriétaire pour éviter deux pipelines.

T005 : tests et documentation terminés, glisser natif vérifié et confirmé par l’utilisateur. Revue non admise. Preuves partielles : option désactivée et Échap non enregistrés en natif.
