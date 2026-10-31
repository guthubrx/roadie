# Audit de réutilisation
Statut : PASS. Aucun doublon évident à arbitrer.
| Besoin | Existant retenu | Décision |
|---|---|---|
| Session souris | UserInputActivity/GestureSession | Étendre les callbacks, pas de second moniteur |
| Géométrie | BSPTree/BSPDivider/CommandTreeGeometry | Préparer les séparations et réutiliser place |
| Writer | SnapshotService/WindowFrameWriting/AXWindowFrameWriter | Extension révocable et distribution asynchrone |
| Persistance | StageStore.mutateChecked | Une transaction finale |
| Cadence native | Pas de runtime live natif existant | Runtime de coordination nécessaire |
## Gate avant tasks
- [x] Plan lu et code existant inspecté.
- [x] Aucun doublon évident laissé sans décision.
- [x] Toutes les nouvelles responsabilités ont une exigence utilisateur.
