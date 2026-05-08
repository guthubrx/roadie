# Quickstart: Roadie Ecosystem Upgrade

## 1. Valider la configuration

```bash
roadie rules validate --config ~/.roadies/config.toml
roadie rules list --json --config ~/.roadies/config.toml
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
roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json --config ~/.roadies/config.toml
```

Résultat attendu :

- informations fenêtre stables.
- liste des règles matchées, non matchées et actions prévues.

## 5. Piloter le layout

```bash
roadie layout insert right
roadie layout split vertical
roadie layout flatten
roadie layout zoom-parent
roadie focus back-and-forth
roadie desktop back-and-forth
roadie desktop summon 2
roadie stage move-to-display 2
```

Résultat attendu :

- le layout change sans casser l'arbre existant.
- chaque commande produit un événement `command.*`.

## 6. Grouper des fenêtres

```bash
roadie group create terminals 12345 67890
roadie group focus terminals 67890
roadie group list
```

Résultat attendu :

- le groupe occupe un seul emplacement dans le layout.
- le focus passe entre les membres sans déplacer les autres fenêtres du stage.

## 7. Query API

```bash
roadie query state
roadie query displays
roadie query desktops
roadie query stages
roadie query groups
roadie query rules
roadie query health
roadie query events
```

Résultat attendu :

- chaque commande retourne un JSON `{ "kind": "...", "data": ... }`.
- les anciennes commandes `state dump`, `tree dump` et `windows list --json` restent disponibles.

## Validation manuelle

- 2026-05-08 : `swift run roadie events subscribe --from-now --initial-state` exécuté avec interruption contrôlée après démarrage; la commande compile et démarre le flux JSONL.
