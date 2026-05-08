# Démarrage Rapide : Roadie Control & Safety

## Préconditions

```bash
git switch 003-roadie-control-safety
make build
make test
```

## Scénario 1 : Control Center

1. Demarrer Roadie.
2. Ouvrir l'item de barre de menus Roadie.
3. Verifier que le menu affiche daemon, config, desktop/stage actif et erreurs recentes.
4. Ouvrir les reglages.
5. Declencher le reload de config depuis l'UI.

Validation CLI equivalente :

```bash
roadie control status --json
roadie config reload --json
```

## Scénario 2 : Safe config reload

1. Charger une config valide.
2. Sauvegarder un `roadies.toml` invalide.
3. Lancer :

```bash
roadie config reload --json
roadie query events
```

Attendu : statut `failed_keeping_previous`, evenement `config.reload_failed`, comportement precedent conserve.

## Scénario 3 : Restore safety

1. Demarrer Roadie avec restore safety active.
2. Verifier le snapshot :

```bash
roadie restore snapshot --json
```

3. Quitter Roadie proprement et verifier que les fenetres restent visibles.
4. Simuler la disparition du daemon dans un test automatise et verifier que le watcher applique la restauration.

## Scénario 4 : Transient windows

1. Ouvrir un panneau open/save dans une app.
2. Provoquer un tick de layout ou un changement de focus.
3. Verifier :

```bash
roadie transient status --json
roadie query events
```

Attendu : Roadie detecte le transient, suspend les adaptations non essentielles, puis reprend apres fermeture.

## Scénario 5 : Layout persistence v2

1. Creer un layout avec stages/desktops/groups.
2. Sauvegarder l'etat.
3. Redemarrer des apps de test avec nouveaux IDs.
4. Lancer un dry-run :

```bash
roadie state restore-v2 --dry-run --json
```

Attendu : matches non ambigus avec scores; conflits explicites.

## Scénario 6 : Width presets/nudge

```bash
roadie layout width next
roadie layout width nudge 0.05
roadie layout width ratio 0.8 --all
```

Attendu : application sur layouts compatibles, rejet structure sur layouts incompatibles.

## Validation finale

```bash
make build
make test
roadie config validate
```
