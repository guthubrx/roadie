# Audit de réutilisation — session 024

**Statut : PASS.** Le plan étend les trois chemins existants.

| Item | Existant réutilisé | Décision |
|---|---|---|
| Appartenances initiales | RoadieState et StageState, dans Sources/RoadieStages/RoadieState.swift | Construction groupée ; assignWindow conservé pour les déplacements |
| Snapshot | SnapshotService.reconcile, Sources/RoadieDaemon/DaemonSnapshot.swift | Collecter les affectations ; aucune seconde réconciliation |
| Scopes faisant foi | LayoutMaintainer.authoritativeModelScopes | Dédupliquer avant le validateur existant |
| Rapprochement | PersistentStageState.reconcileWindowIDs, signature et distance de cadre | Index local à la passe ; même score et mêmes seuils |
| Tests | Swift Testing, fixtures PowerUser et tests de persistance/groupes | Tests 024 et scénarios historiques conservés |

Aucun index géométrique de remplacement existant trouvé dans le rapprochement.
Les arbres BSP représentent les séparations des fenêtres ; ils ne répondent pas
aux requêtes de proximité sur centres et dimensions.

- [x] Aucun service ou contrat reconstruit.
- [x] Chaque item du plan a une décision de réutilisation.
- [x] Standards et constitution consultés.
- [x] Plans 016, 017 et corrections 022 réutilisés.
