# Modèle de données — session 029

## Entités existantes

### Destruction confirmée

Ensemble en mémoire `destroyedWindowIDs` dans `SnapshotProcessState`, complété
par la date de preuve et l'état de reprise courte.

- Ajout : notification AX de destruction d'une fenêtre.
- Conservation pour l'arbre : contrat historique inchangé.
- Validité pour l'appartenance : cinq secondes.
- Reprise : toutes les 50 ms, dix fois au maximum par identifiant, tant que
  l'identifiant reste dans `stageManagedWindowIDs`.
- Consommation : après sa disparition de l'ensemble des fenêtres vivantes et
  après la réconciliation persistante.

Le compteur augmente seulement dans un snapshot écrivain (`producer: true`).
Un snapshot lecteur ne le modifie pas. Une notification répétée ne remet ni la
date ni le compteur à zéro. L'échéance disparaît à la consommation, après cinq
secondes ou quand le compteur atteint dix.

### Membre persistant de stage

`PersistentStageMember` conserve l'identifiant, le titre, le cadre,
`lastSeenAt`, `missingSince` et le nouveau champ optionnel `confirmedClosedAt`.

- Absence non confirmée : renseigner `missingSince` et conserver le membre.
- Destruction récente, confirmée et absente de `stageManagedWindowIDs` :
  renseigner `confirmedClosedAt` et `missingSince`, puis conserver le membre.
- Identifiant encore vivant : ne pas supprimer le membre, même si un ancien
  événement de destruction existe.
- Fenêtre revue ou remappée après relance : effacer `confirmedClosedAt`.
- Purge : réutiliser la purge existante des membres absents. Le marqueur ne
  prolonge pas la durée de vie persistante du membre.

### Stage visible du navrail

`RailDisplayContent` contient seulement les stages avec au moins un membre
représenté. Un membre avec `confirmedClosedAt` n'est pas représenté, sauf si
son identifiant est de nouveau vivant. Le dernier membre masqué retire donc la
stage du navrail sans supprimer son appartenance persistante.

## Invariants

- Une fenêtre dans `stageManagedWindowIDs` gagne contre tout événement portant
  le même ID.
- Une destruction répétée est idempotente.
- Une preuve de plus de cinq secondes ne retire jamais une appartenance.
- Les reprises courtes sont bornées et cessent après dix passages.
- Une absence non confirmée conserve la grâce actuelle de 15 secondes.
- Une fermeture confirmée masque le membre dans le navrail sans le supprimer du
  `StageStore`.
