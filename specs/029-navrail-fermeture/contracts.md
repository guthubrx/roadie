# Contrats internes — session 029

## AX vers snapshot

Entrée : `AXWindowEvent(name: kAXUIElementDestroyedNotification, pid, windowID)`.

Effets autorisés :

- enregistrer `windowID` comme détruit ;
- oublier son cadre écrit ;
- invalider les caches AX du processus ;
- demander une passe événementielle.

Effets interdits : commande de layout directe, changement de focus ou boucle
de consultation permanente ou non bornée.

## Snapshot vers StageStore

Pour chaque `windowID` détruit :

- si l'identifiant est encore dans `stageManagedWindowIDs`, conserver le membre
  et programmer une reprise bornée ;
- sinon, si la preuve date de moins de cinq secondes, renseigner
  `confirmedClosedAt` et `missingSince` sans supprimer le membre, ses groupes
  ou ses focus ;
- sinon appliquer la grâce normale d'une absence non confirmée ;
- consommer ensuite le marqueur.

Les pins, signets et surcharges de placement gardent leur cycle de vie actuel.
Les fenêtres sans identifiant CoreGraphics utilisable gardent aussi le chemin
d'absence existant.

La purge existante des membres absents reste seule responsable de leur durée
de vie persistante. Le nouveau marqueur n'ajoute aucune conservation.

## StageStore vers navrail

Une écriture qui change les membres ou `confirmedClosedAt` modifie la signature du rail. Le watcher
existant regroupe l'événement pendant 20 ms. La reconstruction retire les
cartes absentes. Une stage sans carte est absente de la même publication.

Le filtre du navrail donne la priorité à une fenêtre redevenue vivante, puis
exclut un membre marqué fermé avant d'appliquer la grâce de 15 secondes aux
absences ordinaires.
