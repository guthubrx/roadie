# Quickstart : valider le parking d'écran

## Préconditions

- Roadie construit et lancé depuis la branche `031-display-stage-parking`.
- Deux écrans branchés.
- Au moins deux stages non vides sur l'écran secondaire.
- Une stage nommée sur l'écran secondaire, par exemple `Perso`.

## Vérification locale rapide

```bash
make build
./scripts/roadie config validate
./scripts/start
./scripts/status
```

## Validation automatisée ciblée

```bash
./scripts/with-xcode swift test --filter DisplayParkingServiceTests
./scripts/with-xcode swift test --filter DisplayTopologyTests
./scripts/with-xcode swift test --filter SnapshotServiceTests
```

Ces tests doivent passer avant tout essai manuel de débranchement/rebranchement.

## Scénario 1 : débrancher un écran

1. Sur l'écran secondaire, créer ou ouvrir plusieurs fenêtres dans deux ou trois stages.
2. Nommer au moins une stage.
3. Débrancher l'écran secondaire.
4. Attendre la période de stabilisation.

Résultat attendu :

- Les fenêtres de l'écran disparu restent visibles ou récupérables sur l'écran restant.
- Les stages de l'écran disparu apparaissent comme stages distinctes.
- La stage active de l'écran restant n'est pas remplacée par un mélange de toutes les fenêtres.
- Les logs indiquent un parking ou une transition non destructive.

## Scénario 2 : travailler pendant le parking

1. Renommer une stage rapatriée.
2. Déplacer une fenêtre vers une autre stage rapatriée.
3. Changer le mode d'organisation d'une stage rapatriée.
4. Fermer une fenêtre dans une stage rapatriée.

Résultat attendu :

- Les changements restent visibles.
- Aucun heal ne restaure une ancienne copie.
- Aucun layout ne boucle ou ne mélange les stages.

## Scénario 3 : rebrancher le même écran

1. Rebrancher l'écran secondaire.
2. Attendre la période de stabilisation.

Résultat attendu :

- Les stages rapatriées retournent sur l'écran reconnu.
- Les changements faits pendant l'absence sont conservés.
- Les stages natives de l'écran resté branché gardent leur ordre et leur contenu.

## Scénario 4 : ambiguïté volontaire

1. Brancher un écran différent ou un écran similaire que Roadie ne peut pas reconnaître avec confiance.

Résultat attendu :

- Roadie ne restaure pas automatiquement de manière destructive.
- Les stages rapatriées restent visibles sur l'écran hôte.
- Un diagnostic indique que la restauration est ambiguë ou refusée.

## Tests ciblés attendus

```bash
./scripts/with-xcode swift test --filter DisplayParkingServiceTests
./scripts/with-xcode swift test --filter SnapshotServiceTests
./scripts/with-xcode swift test --filter DisplayTopologyTests
make build
```

## Critères d'échec

- Toutes les fenêtres de l'écran disparu se retrouvent dans une seule stage existante.
- Une fenêtre vivante devient invisible ou impossible à récupérer.
- Un écran rebranché ambigu reçoit automatiquement des stages.
- Les changements faits pendant le parking sont perdus.
- Le layout oscille pendant plusieurs secondes après stabilisation.
