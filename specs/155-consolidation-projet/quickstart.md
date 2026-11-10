# Démarrage rapide - 155 consolidation du projet

Ce document s'adresse à l'agent qui exécute les tâches. Lis-le en entier avant la tâche T001.

## 1. Où travailler

- Dossier de travail : `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/155-consolidation-projet`
- Branche : `155-consolidation-projet`
- Lance toutes les commandes depuis ce dossier. Ne va jamais dans le dépôt principal
  (`/Users/moi/Nextcloud/10.Scripts/39.roadie`).
- Si une commande a besoin d'un autre dossier, utilise un sous-shell : `( cd dossier && commande )`.

## 2. Les trois fichiers à suivre

| Fichier | Rôle |
|---------|------|
| `specs/155-consolidation-projet/tasks.md` | La liste des tâches, dans l'ordre. Coche une tâche quand son contrôle a réussi. |
| `specs/155-consolidation-projet/recettes.md` | Pour chaque tâche : la commande exacte, le texte avant et après, le contrôle, le résultat attendu. |
| `specs/155-consolidation-projet/decisions.md` | Les décisions qui attendent l'utilisateur. Tu ne les traites pas. |

## 3. Méthode : tu n'écris presque rien à la main

Les changements sont déjà préparés. Un outil les applique. Pour une tâche `T0xx` préparée :

```bash
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T0xx --check
python3 -I -B specs/155-consolidation-projet/tools/appliquer.py T0xx
```

1. La première commande contrôle sans écrire. Elle doit finir par `OK T0xx : contrôle réussi`.
2. La seconde écrit. Elle doit finir par `OK T0xx : N fichier(s) écrit(s).`
3. Relancer une tâche déjà faite ne change rien : l'outil affiche `déjà fait` ou `déjà là`.

Liste des tâches préparées : `python3 -I -B specs/155-consolidation-projet/tools/appliquer.py --liste`.

Les tâches sans préparation (contrôles, commits, `git mv`, outils `deplacer_journal.py`,
`extraire_fournisseur.py`, `inventaire.py`) ont leurs commandes exactes dans `recettes.md`.

Le code et les textes ont été écrits et essayés pendant la préparation (voir `research.md`,
R16). Ton travail est de les appliquer dans l'ordre et de contrôler chaque résultat.

## 4. Règle R0 : arrêt sans adaptation

Arrête la tâche et signale le problème dans ces cas :

- `appliquer.py` affiche `ARRÊT (règle R0)` ou une ligne `ERREUR :`.
- Un outil finit par un code de retour différent de 0.
- Un contrôle ne donne pas le résultat attendu écrit dans `recettes.md`.
- La compilation échoue (sauf le cas attendu du point 6).

Dans ces cas :

1. Ne corrige pas le fichier à la main. N'invente pas un autre changement.
2. Ne coche pas la tâche.
3. Écris dans ton compte rendu : l'identifiant de la tâche, la commande lancée, le message
   d'erreur exact.
4. N'exécute aucune tâche suivante, même dans une autre user story. Les contrôles
   suivants supposent que les tâches précédentes sont terminées et committées
   (`tasks.md`, section « Dependencies & Execution Order »).
5. Laisse les fichiers dans leur état. N'annule rien (`git checkout`, `git reset` et
   `git stash` sont interdits). Rends ton compte rendu.

## 5. Commandes de contrôle

| But | Commande | Résultat attendu |
|-----|----------|------------------|
| Suite complète | `./scripts/test --no-parallel` | Dernière ligne `Test run with N tests in M suites passed`. Environ 80 secondes après la compilation. |
| Un groupe de tests | `./scripts/test --no-parallel --filter NomDeLaSuite` | `Test run with … passed` |
| Tests des scripts | `python3 -I -B -m unittest discover -s scripts/tests` | `Ran 28 tests` puis `OK` |

Garde toujours `--no-parallel`. Sans cette option, des tests sensibles au temps échouent
quand la machine est chargée.

Pour lire seulement la fin d'une longue sortie :

```bash
./scripts/test --no-parallel > /tmp/roadie155-test.log 2>&1; echo "exit=$?"
grep -E "Test run with|recorded an issue" /tmp/roadie155-test.log | tail -5
```

## 6. Ordre et commits

- Exécute les tâches dans l'ordre de `tasks.md`, une seule à la fois. Aucune tâche n'est
  parallèle.
- Après une tâche « tests d'abord » (T006, T025, T036), ne lance pas les tests : la
  compilation échoue jusqu'à la tâche de code suivante. C'est attendu.
- Un commit par user story, à la tâche de contrôle indiquée. Nomme les fichiers :
  `git add -- fichier1 fichier2`, puis `git commit -m "type(155): Description"`.
- N'utilise jamais `git commit -a`, `git add .` ni `git add -A`.
- Le message de commit est exactement celui de `recettes.md`. N'ajoute aucune ligne
  (pas de `Co-Authored-By`, pas de signature, pas de mention d'outil).
- Ne modifie pas `git config`.

## 7. Pièges connus

| Piège | Signe | Remède |
|-------|-------|--------|
| P1 - build de test périmé | Les tests plantent au signal 11 (« outlined destroy ») après un changement de `RoadieCore` | `rm -rf .build/arm64-apple-macosx/debug/RoadieTilerTests.build`, puis relance les tests |
| P2 - symbole introuvable | « Undefined symbols … TargetModeConfig.init » à l'édition de liens | `touch Sources/RoadieDaemon/OverviewController.swift`, puis relance |
| P3 - test sensible au temps | Un test hors de la spec 155 échoue une fois. Cas déjà vu : `Spec151ModifierGestureTests.aNewGenerationNeverRestoresAnObsoleteLayout` | Relance ce test seul : `./scripts/test --no-parallel --filter Spec151ModifierGestureTests`. S'il échoue deux fois de suite : règle R0 |
| P4 - relevé de couverture | Un fichier `default.profraw` apparaît à la racine | `rm -f default.profraw`. Ne le committe jamais |
| P5 - avertissement sans gravité | « failed loading cached manifest … Not a directory » | Rien à faire : ce n'est pas une erreur |

## 8. Actions interdites

- `git push`, création de tag, publication d'une release.
- `make install`, `make uninstall`, `scripts/install` : l'application installée de
  l'utilisateur ne doit pas changer.
- `kill` d'un processus, quel qu'il soit.
- Toute dépense, tout appel réseau autre que `roadie update check` en T040.
- Lancer le workflow GitHub de T031.
- Modifier un fichier que la tâche ne nomme pas.
- Traiter une décision de `decisions.md` (licence, version 0.14.0, notarisation, CI
  automatique, retrait d'images).
- Supprimer le dossier `.build` entier ou le worktree.

## 9. Fin du travail

La dernière tâche est T045. Ton compte rendu final donne :

- le nombre de tâches cochées sur 45 ;
- le résultat de la suite complète (nombre de tests, nombre de suites, code de retour) ;
- chaque tâche non terminée, avec la commande et l'erreur ;
- le statut : `Implemented` seulement si les 45 tâches sont cochées, sinon `In Progress`.

L'installation, la revue, l'audit et la livraison ne font pas partie de tes tâches.
