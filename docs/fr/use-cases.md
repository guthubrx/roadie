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

## 7. Avant une operation risquee

Objectif : garder une porte de retour explicite et verifier le snapshot utilise aussi par le watcher crash.

```bash
./bin/roadie config reload --json
./bin/roadie restore snapshot --json
./bin/roadie restore status
```

Si les frames doivent etre restaurees explicitement :

```bash
./bin/roadie restore apply --yes
```

Ce restore matche les fenetres par ID courant. Le watcher crash utilise le meme mecanisme seulement si le daemon disparait sans sortie propre; il ne tourne pas dans le chemin focus/bordure.

## 8. Administration locale raisonnable

Objectif : eviter l'accumulation de logs et backups.

```bash
./bin/roadie cleanup --dry-run
./bin/roadie cleanup --apply
```

Commencer par `--dry-run` permet de voir les fichiers candidats avant suppression ou rotation.

## 9. Navigation clavier avec labels

Objectif : sauter vers une fenetre, une stage, un ecran, un desktop ou un
bookmark sans memoriser les IDs internes.

```bash
./bin/roadie targets interactive --source all
./bin/roadie targets pick work --action switch
./bin/roadie targets inspect A --json
```

A utiliser quand :

- le navrail est visible mais la cible est plus simple a taper qu'a cliquer;
- un script ou un agent a besoin d'une liste structuree de destinations;
- une recherche ambigue doit echouer proprement au lieu de deplacer des fenetres.

## 10. Ciblage spatial quand Accessibility ne voit pas un controle

Objectif : cibler une zone visuelle meme quand l'application n'expose pas
d'element Accessibility utile.

```bash
./bin/roadie grid interactive --scope display --duration 10
./bin/roadie grid interactive --scope focused_window --duration 10
```

Utilise **Grille Ecran** pour cibler un ecran complet ou changer de zone entre
ecrans. Utilise **Grille Fenetre** quand l'interaction reste dans la fenetre
focussee : lecteur video, canvas, webview ou panneau applicatif dense.

## 11. Capture de macros courtes

Objectif : enregistrer une courte manipulation souris avec coordonnees et
contexte semantique de cible.

```bash
./bin/roadie record start demo --duration 10
./bin/roadie record inspect demo --json
./bin/roadie record replay demo
```

Les recordings gardent une meilleure cible Roadie ou Accessibility quand elle
existe, plus un fallback grille. Le replay peut donc preferer les cibles stables
et n'utiliser les coordonnees qu'en dernier recours.
