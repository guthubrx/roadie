# Implémentation — session 029

## Résultat

Roadie propage maintenant une fermeture confirmée jusqu'au `StageStore`.
Le navrail masque immédiatement le membre absent. Si ce membre était le dernier
de sa stage, le filtre existant masque la stage dans la même reconstruction.

Le membre persistant n'est pas supprimé immédiatement. Il garde son
`missingSince`. Cette règle conserve la purge existante et le rattachement de
SPEC-016 après la relance d'une application.

## Changements

- `SnapshotProcessState` conserve une preuve horodatée par identifiant.
- Une preuve reste utilisable pendant cinq secondes.
- Un snapshot écrivain peut programmer dix reprises de 50 ms au maximum.
- Un snapshot lecteur ne consomme pas le budget de reprise.
- Une destruction reçue pendant l'énumération reste en attente de la passe
  suivante.
- `PersistentStageMember` gagne le champ optionnel `confirmedClosedAt`.
- Une fenêtre vivante ou remappée efface ce champ.
- La signature du watcher inclut le marqueur de fermeture.
- Le rail donne toujours priorité à une fenêtre vivante. Sinon, il masque un
  membre marqué comme fermé avant la grâce normale de 15 secondes.

## Vérification

- Tests ciblés : 117 tests, 5 suites, succès.
- Suite complète : 1466 tests, 156 suites, succès.
- Revue finale : approuvée, aucun défaut P0, P1 ou P2.
- Audit v14 : note A, aucun finding, validateur conforme.
- Build Release : succès.
- Application installée et signée : succès.
- Runtime : PID 93111, santé du démon conforme.
- Fermeture réelle observée : le marqueur persistant est écrit et le
  rafraîchissement du rail suit la détection de disparition en 90 ms.

## Auto-revue constitutionnelle

La modification réutilise le watcher, le scheduler et le `StageStore`
existants. Elle n'ajoute aucune boucle permanente ni dépendance. Les reprises
sont bornées. Le coût reste linéaire selon le nombre de membres persistants.

La modification ne déclenche aucune commande de layout. Elle ne supprime pas
les données nécessaires à la restauration. Elle préserve donc la séparation
entre l'état visuel immédiat et la durée de vie persistante.
