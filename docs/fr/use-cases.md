# Cas d'usage

## 1. Poste de developpement quotidien

Objectif : garder le code, les terminaux et la documentation organises sans manipuler les fenetres a la souris.

Setup conseille :

- Desktop `1` : developpement.
- Stage `dev` : editeur + terminal principal.
- Stage `docs` : navigateur/documentation.
- Stage `comms` : messagerie.

Commandes :

```bash
./bin/roadie desktop label 1 Dev
./bin/roadie stage rename 1 Dev
./bin/roadie stage create docs
./bin/roadie stage create comms
./bin/roadie mode masterStack
```

Rule typique :

```toml
[[rules]]
id = "docs-browser"
priority = 10

[rules.match]
app_regex = "Safari|Firefox|Chrome"
title_regex = "Docs|Documentation|README"

[rules.action]
assign_stage = "docs"
scratchpad = "research"
emit_event = true
```

## 2. Operations multi-ecran

Objectif : garder un ecran principal pour le travail actif et deplacer une stage complete vers un ecran secondaire.

```bash
./bin/roadie display list
./bin/roadie stage move-to-display 2
./bin/roadie desktop summon 2
```

Cas concret :

- ecran 1 : incident actif;
- ecran 2 : logs, dashboards, documentation;
- `stage move-to-display` deplace le contexte sans recreer les fenetres.

## 3. Workflow recherche/documentation

Objectif : grouper plusieurs fenetres de documentation et les retrouver via queries.

```bash
./bin/roadie windows list
./bin/roadie group create research 12345 67890
./bin/roadie group focus research 67890
./bin/roadie query groups
```

Integration possible :

```bash
./bin/roadie query groups | jq '.data'
```

## 4. Barre de statut locale

Objectif : afficher la fenetre active, la stage et les evenements importants.

```bash
./bin/roadie events subscribe --from-now --initial-state --scope window --scope stage
```

Le consommateur doit :

- ignorer les champs inconnus;
- utiliser `type`, `scope`, `subject` et `payload`;
- tolerer les nouveaux evenements.

## 5. Validation avant changement de config

Objectif : eviter qu'une rule TOML cassee perturbe la session.

```bash
./bin/roadie rules validate --config ~/.config/roadies/roadies.toml
./bin/roadie rules explain --app Terminal --title roadie --role AXWindow --stage dev --json
```

Workflow recommande :

1. modifier `roadies.toml`;
2. lancer `rules validate`;
3. tester une fenetre representative avec `rules explain`;
4. redemarrer Roadie si necessaire.

## 6. Recuperation apres incoherence d'etat

Objectif : reparer l'etat local sans supprimer toute la configuration.

```bash
./bin/roadie state audit
./bin/roadie state heal
./bin/roadie daemon heal
./bin/roadie daemon health
```

Utiliser cette sequence apres :

- deconnexion/reconnexion d'ecran;
- fermeture brutale d'apps;
- changement de branche ou rebuild.

