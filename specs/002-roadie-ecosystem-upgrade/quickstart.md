# Quickstart: Roadie Ecosystem Upgrade

## 1. Valider la configuration

```bash
roadie rules validate --config ~/.roadies/config.toml
```

Résultat attendu :

- sortie lisible si tout est valide.
- sortie JSON disponible avec `--json`.
- code retour non-zéro si une règle est invalide.

## 2. Observer Roadie en direct

```bash
roadie events subscribe --from-now --initial-state
```

Résultat attendu :

- première ligne `state.snapshot`.
- lignes suivantes en JSONL dès qu'une fenêtre, un desktop, un stage, une règle ou une commande change.

## 3. Brancher une barre ou un script

```bash
roadie events subscribe --from-now --type window.focused --type desktop.changed
```

Le script consommateur doit ignorer les champs inconnus et ne dépendre que du contrat `schemaVersion=1`.

## 4. Diagnostiquer une fenêtre

```bash
roadie query windows --json
roadie rules explain --window 12345 --json
```

Résultat attendu :

- informations fenêtre stables.
- liste des règles matchées, non matchées et actions prévues.

## 5. Piloter le layout

```bash
roadie layout insert east
roadie layout split vertical
roadie focus back-and-forth
```

Résultat attendu :

- le layout change sans casser l'arbre existant.
- chaque commande produit un événement `command.*`.

## 6. Grouper des fenêtres

```bash
roadie group create --window 12345 --window 67890
roadie group focus next
```

Résultat attendu :

- le groupe occupe un seul emplacement dans le layout.
- le focus passe entre les membres sans déplacer les autres fenêtres du stage.
