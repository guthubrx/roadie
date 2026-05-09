# Quickstart : Performance ressentie Roadie

## Objectif

Valider progressivement que Roadie devient plus fluide sans réintroduire les oscillations de stage/desktop ni les lectures qui modifient l'état.

## Préparation

```bash
git status --short
make test
make build
```

Les tests doivent être verts avant de commencer une tranche d'optimisation.

## Baseline avant optimisation

1. Lancer Roadie sans Control Center.

```bash
./scripts/start --no-control-center
./bin/roadie daemon health
```

2. Exécuter des scénarios représentatifs :

- Changer de stage par position utilisateur.
- Changer de desktop Roadie.
- Sélectionner via AltTab une fenêtre dans un stage inactif.
- Sélectionner via AltTab une fenêtre dans un desktop Roadie inactif.
- Cliquer dans le rail si activé.

3. Consulter le diagnostic attendu après instrumentation :

```bash
./bin/roadie performance summary
./bin/roadie performance recent --limit 20
./bin/roadie query performance
```

## Validation par tranche

### Tranche 1 - Instrumentation

Critère : les commandes de performance retournent des données structurées sans modifier l'état Roadie.

```bash
make test
./bin/roadie performance summary --json
./bin/roadie query performance
```

### Tranche 2 - Stage/Desktop directs

Critère : une commande stage/desktop ne montre aucune activation intermédiaire et produit une mesure sous seuil.

```bash
./bin/roadie stage 1
./bin/roadie stage 2
./bin/roadie desktop 1
./bin/roadie desktop 2
./bin/roadie performance recent --limit 10
```

### Tranche 3 - AltTab prioritaire

Critère : AltTab vers une fenêtre gérée active directement le bon contexte et publie une interaction `alt_tab_activation`.

```bash
./bin/roadie performance recent --limit 20
./bin/roadie events tail 30
```

### Tranche 4 - Déplacements redondants

Critère : les actions déjà proches de leur cible réduisent les déplacements inutiles et gardent les tests existants verts.

```bash
make test
./bin/roadie performance summary
```

### Tranche 5 - Rail et tâches secondaires

Critère : activer le rail ou les diagnostics ne dégrade pas significativement les timings stage/desktop.

```bash
./scripts/start --no-control-center
./bin/roadie performance summary
```

## Validation finale

```bash
make test
make build
./bin/roadie daemon health
git status --short
```

La feature est prête quand :

- Les tests de régression passent.
- Les interactions lentes produisent un diagnostic actionnable.
- Stage, desktop et AltTab respectent les objectifs de la spec dans les scénarios contrôlés.
- Le working tree est propre après commit.
