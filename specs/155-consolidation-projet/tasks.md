# Tasks: 155 - Consolidation du projet

**Input** : documents de conception dans `specs/155-consolidation-projet/`
**Prérequis** : `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`, `reuse-audit.md` (statut PASS)

**Tests** : inclus. Les stories 2, 3, 7 et 10 ajoutent du code : leurs tests sont écrits avant le code.

**Organisation** : une phase par user story. Chaque phase finit par un contrôle et un commit local.

## Mode d'emploi (à lire avant T001)

1. Lis `specs/155-consolidation-projet/quickstart.md` en entier. Il donne la méthode, la règle R0, les commandes de contrôle, les pièges P1 à P5 et les actions interdites.
2. Fais les tâches dans l'ordre, de T001 à T045. Ne saute aucune tâche. Ne change pas l'ordre.
3. Pour chaque tâche, ouvre sa fiche dans `specs/155-consolidation-projet/recettes.md` (titre `## T0NN`). Lance les commandes de la fiche, telles qu'elles sont écrites.
4. Compare chaque résultat avec le « Résultat attendu » de la fiche. S'il diffère : règle R0 (arrêt, pas d'adaptation, compte rendu). Après un arrêt R0, ne fais aucune autre tâche, même dans une autre user story.
5. Coche la tâche ici (`- [x]`) seulement après le résultat attendu.
6. N'écris jamais le code à la main : `tools/appliquer.py` l'écrit à partir de `tools/remplacements.json` et de `gabarits/`. Deux saisies à la main seulement : T001 et T044 (valeurs observées).
7. Interdits pendant tout le travail : `git push`, `git commit -a`, `git stash`, `make install`, `scripts/install`, publication d'une release, lancement du workflow GitHub, toute mention d'une IA dans un commit.

Toutes les commandes se lancent depuis la racine du worktree :
`/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/155-consolidation-projet`

## Format: `[ID] [P?] [Story] Description`

- **[P]** : tâche parallélisable. Aucune tâche n'a cette marque ici : l'ordre est strict.
- **[Story]** : user story de `spec.md` (US1 à US11). Les tâches de Setup et de Polish n'ont pas de marque.
- Chaque ligne donne le fichier touché, la fiche à suivre et le résultat observable.

## Path Conventions

- Code : `Sources/RoadieCore/`, `Sources/RoadieDaemon/`, `Sources/roadied/`
- Tests : `Tests/RoadieDaemonTests/`
- Scripts : `scripts/`, `Makefile`
- Documentation : `README.md`, `README.fr.md`, `docs/`, `CHANGELOG.md`, `AGENTS.md`
- Outils et modèles de cette spec : `specs/155-consolidation-projet/tools/`, `specs/155-consolidation-projet/gabarits/`

---

## Phase 1: Setup

**But** : mesurer l'état de départ. Ces mesures servent de comparaison à la fin.

- [ ] T001 Relever la base de référence dans `specs/155-consolidation-projet/validation/baseline.md` (fiche T001). Résultat : `./scripts/test --no-parallel` rend `exit=0` avec 2523 tests dans 383 suites ; `grep -c "À REMPLIR"` sur le fichier rend `0` ; commit `docs(155): Relever la base de référence`.

---

## Phase 2: Foundational

Aucune tâche. Les user stories ne partagent aucun prérequis de code.
Deux dépendances d'ordre existent entre stories ; elles sont listées dans « Dependencies & Execution Order ».

---

## Phase 3: User Story 1 - Documentation publique propre (Priority: P1) 🎯 MVP

**But** : aucun chemin personnel dans le README, un numéro unique par décision, aucune sauvegarde suivie par Git.

**Test indépendant** : `grep -c "/Users/moi" README.md README.fr.md` rend `README.md:0` et `README.fr.md:0`.

### Implementation for User Story 1

- [ ] T002 [US1] Retirer le chemin personnel de `README.fr.md` (fiche T002). Résultat : `grep -c "/Users/moi" README.md README.fr.md` rend `README.md:0` et `README.fr.md:0`.
- [ ] T003 [US1] Renommer `docs/decisions/013-native-command-input.md` en `docs/decisions/030-native-command-input.md` par `git mv`, puis corriger son titre (fiche T003). Résultat : `ls docs/decisions | grep -c '^013-'` rend `1` ; la première ligne du fichier renommé est `# 030 - Champ natif dans la boîte de commandes`.
- [ ] T004 [US1] Retirer `.specify/memory/constitution.md.bak-20260508-143829` du suivi Git et ajouter la règle dans `.gitignore` (fiche T004). Résultat : `git ls-files .specify/memory | grep -c "bak-"` rend `0` ; le fichier existe encore sur le disque.
- [ ] T005 [US1] Contrôler la story et committer `README.fr.md`, `docs/decisions/030-native-command-input.md`, `.gitignore` (fiche T005). Résultat : commit `docs(155): Nettoyer la documentation publique` ; `git status --short` n'affiche rien.

**Checkpoint** : la documentation publique est propre. Un commit.

---

## Phase 4: User Story 2 - Version unique et identité du build (Priority: P1)

**But** : la version est écrite à un seul endroit ; l'application installée connaît le commit de son build.

**Test indépendant** : sur un bundle temporaire construit avec le commit `abc12345`, `roadied --version` affiche `roadied 0.13.0 (abc12345)`.

### Tests for User Story 2 (écrits avant le code)

- [ ] T006 [US2] Créer `Tests/RoadieDaemonTests/Spec155BuildIdentityTests.swift` à partir du gabarit (fiche T006). Résultat : `OK T006 : 1 fichier(s) écrit(s).` Ne lance pas les tests : la compilation échoue jusqu'à la fin de T007, c'est attendu.

### Implementation for User Story 2

- [ ] T007 [US2] Ajouter `RoadieVersion.buildCommit`, `RoadieVersion.display` et le champ `DaemonStatus.buildCommit` dans `Sources/RoadieDaemon/DaemonHealth.swift` (fiche T007). Résultat : `OK T007 : 1 fichier(s) écrit(s).`
- [ ] T008 [US2] Afficher le commit dans `roadied --version` dans `Sources/roadied/main.swift` (fiche T008). Résultat : `./scripts/test --no-parallel --filter Spec155BuildIdentityTests` affiche `Test run with 4 tests in 1 suite passed`.
- [ ] T009 [US2] Accepter un quatrième argument (le commit) dans `scripts/build-app-bundle` et l'écrire dans la clé `RoadieBuildCommit` (fiche T009). Résultat : `bash -n scripts/build-app-bundle; echo "syntaxe=$?"` affiche `syntaxe=0`.
- [ ] T010 [US2] Transmettre le commit depuis `scripts/install` et `scripts/package-dmg` ; lire la version dans `DaemonHealth.swift` depuis `scripts/package-dmg` (fiche T010). Résultat : `install=0`, `dmg=0` ; `grep -rl '0\.13\.0' Sources scripts` rend une seule ligne, `Sources/RoadieDaemon/DaemonHealth.swift`.
- [ ] T011 [US2] Documenter le commit du build dans `specs/016-roadie-stabilization/contracts/daemon-status.md`, `docs/fr/cli.md`, `docs/en/cli.md` et `CHANGELOG.md` (fiche T011). Résultat : `OK T011 : 4 fichier(s) écrit(s).`
- [ ] T012 [US2] Contrôler la story sur un bundle temporaire, lancer la suite complète et committer (fiche T012). Résultat : `roadied 0.13.0 (abc12345)` dans le bundle ; suite `exit=0`, 2527 tests dans 384 suites (le test existant de `roadie --version` y reste vert : FR-008) ; commit `feat(155): Inscrire le commit du build dans la version`. Rien n'est installé.

**Checkpoint** : une publication ne change plus qu'un fichier. Un commit.

---

## Phase 5: User Story 3 - Garde-fous des réglages (Priority: P2)

**But** : un test échoue si un réglage est ajouté sans être déclaré partout.

**Test indépendant** : `./scripts/test --no-parallel --filter Spec155ConfigGuardTests` affiche `Test run with 2 tests in 1 suite passed`.

### Implementation for User Story 3

- [ ] T013 [US3] Ajouter l'accesseur `RoadieConfigLoader.knownKeys()` dans `Sources/RoadieCore/Config.swift` (fiche T013). Résultat : `OK T013 : 1 fichier(s) écrit(s).` Si un signal 11 apparaît à la tâche suivante : piège P1.

### Tests for User Story 3

- [ ] T014 [US3] Créer `Tests/RoadieDaemonTests/Spec155ConfigGuardTests.swift` à partir du gabarit (fiche T014). Résultat : `./scripts/test --no-parallel --filter Spec155ConfigGuardTests` affiche `Test run with 2 tests in 1 suite passed`.
- [ ] T015 [US3] Créer `docs/dev/ajouter-un-reglage.md`, lancer la suite complète et committer (fiche T015). Résultat : suite `exit=0`, 2529 tests dans 385 suites ; commit `test(155): Garder les réglages sous contrôle`.

**Checkpoint** : les réglages sont gardés par deux tests. Un commit.

---

## Phase 6: User Story 4 - Consignes des agents allégées (Priority: P2)

**But** : `AGENTS.md` garde les règles ; le journal des sessions part dans un autre fichier, sans perte.

**Test indépendant** : `wc -c AGENTS.md` rend moins de 8000 ; `deplacer_journal.py --check` rend `OK : 366 lignes de journal conservées, 0 restante dans AGENTS.md`.

### Implementation for User Story 4

- [ ] T016 [US4] Déplacer le journal d'`AGENTS.md` vers `.specify/memory/sessions/journal.md` avec `specs/155-consolidation-projet/tools/deplacer_journal.py` (fiche T016). Résultat : `lignes_deplacees=366` ; `octets_agents=1916`. Ne lance pas l'outil deux fois : la fiche a un garde `test -e`.
- [ ] T017 [US4] Ajouter les sections « Journal des sessions », « Tests » et « Pièges connus » dans `AGENTS.md` (fiche T017). Résultat : `OK T017 : 1 fichier(s) écrit(s).` Cette tâche exige T016.
- [ ] T018 [US4] Contrôler la story et committer `AGENTS.md` et `.specify/memory/sessions/journal.md` (fiche T018). Résultat : `wc -c AGENTS.md` rend moins de 8000 (attendu : environ 3736) ; `grep -c "SPECKIT" AGENTS.md` rend `4` ; commit `docs(155): Alléger les consignes des agents`.

**Checkpoint** : les consignes sont courtes. Un commit.

---

## Phase 7: User Story 5 - Lectures d'accessibilité sûres (Priority: P2)

**But** : une réponse inattendue d'une application ne peut plus faire planter Roadie sur les deux sites recensés.

**Test indépendant** : `grep -c "CFGetTypeID" Sources/RoadieDaemon/AppTargetQueryService.swift` rend `5` (2 avant).

### Implementation for User Story 5

- [ ] T019 [US5] Contrôler le type avant la conversion en `AXUIElement` dans `Sources/RoadieDaemon/AppTargetQueryService.swift` (fiche T019). Résultat : `OK T019 : 1 fichier(s) écrit(s).`
- [ ] T020 [US5] Contrôler le type des valeurs de position et de taille dans `Sources/RoadieDaemon/AppTargetQueryService.swift` (fiche T020). Résultat : `OK T020 : 1 fichier(s) écrit(s).`
- [ ] T021 [US5] Noter le changement dans `CHANGELOG.md`, lancer la suite complète et committer (fiche T021). Résultat : `grep -c "CFGetTypeID" Sources/RoadieDaemon/AppTargetQueryService.swift` rend `5` ; suite `exit=0`, 2529 tests dans 385 suites ; commit `fix(155): Contrôler le type des réponses d'accessibilité`.

**Checkpoint** : deux conversions forcées sont gardées. Un commit.

---

## Phase 8: User Story 6 - Journal sans position des clics (Priority: P2)

**But** : Roadie n'écrit plus la position de chaque clic dans son journal.

**Test indépendant** : `grep -rn "drag.real_press\|drag.real_router_press" Sources/` n'affiche aucune ligne.

### Implementation for User Story 6

- [ ] T022 [US6] Retirer l'événement `drag.real_press` de `Sources/RoadieDaemon/DropPreviewController.swift` (fiche T022). Résultat : `OK T022 : 1 fichier(s) écrit(s).`
- [ ] T023 [US6] Retirer l'événement `drag.real_router_press` de `Sources/RoadieDaemon/RailController.swift` (fiche T023). Résultat : `OK T023 : 1 fichier(s) écrit(s).`
- [ ] T024 [US6] Noter le changement dans `CHANGELOG.md`, lancer la suite complète et committer (fiche T024). Résultat : la recherche des deux événements dans `Sources/` n'affiche aucune ligne, puis `rc=1` ; suite `exit=0`, 2529 tests dans 385 suites ; commit `fix(155): Ne plus journaliser la position des clics`.

**Checkpoint** : le journal ne contient plus la position des clics. Un commit.

---

## Phase 9: User Story 7 - Complétion et couverture (Priority: P3)

**But** : `roadie completion zsh` produit un script valide ; `make coverage` mesure la couverture.

**Test indépendant** : `.build/debug/roadie completion zsh | zsh -n ; echo $?` rend `0`.

### Tests for User Story 7 (écrits avant le code)

- [ ] T025 [US7] Créer `Tests/RoadieDaemonTests/Spec155ShellCompletionTests.swift` à partir du gabarit (fiche T025). Résultat : `OK T025 : 1 fichier(s) écrit(s).` Ne lance pas les tests : la compilation échoue jusqu'à la fin de T027, c'est attendu.

### Implementation for User Story 7

- [ ] T026 [US7] Créer `Sources/RoadieDaemon/ShellCompletion.swift` à partir du gabarit (fiche T026). Résultat : `OK T026 : 1 fichier(s) écrit(s).`
- [ ] T027 [US7] Brancher la commande `completion` dans `Sources/RoadieDaemon/CLICommandRouter.swift` (fiche T027). Résultat : `./scripts/test --no-parallel --filter Spec155ShellCompletionTests` affiche `Test run with 4 tests in 1 suite passed`.
- [ ] T028 [US7] Créer `scripts/coverage`, ajouter la cible `coverage` au `Makefile` et les fichiers de mesure à `.gitignore` (fiche T028). Résultat : `syntaxe=0`, `executable=0`, puis `1` pour `grep -c '^coverage:' Makefile`. Cette tâche exige T004.
- [ ] T029 [US7] Documenter la complétion et la couverture dans `README.md`, `README.fr.md`, `docs/fr/cli.md`, `docs/en/cli.md` et `CHANGELOG.md` (fiche T029). Résultat : `OK T029 : 5 fichier(s) écrit(s).`
- [ ] T030 [US7] Contrôler la complétion, lancer la suite complète puis `make coverage`, et committer (fiche T030). Résultat : `zsh=0` et `bash=64` ; suite `exit=0`, 2533 tests dans 386 suites ; `coverage=0` avec une ligne `coverage : lignes …` ; commit `feat(155): Ajouter la complétion zsh et la mesure de couverture`. Supprime `default.profraw` s'il existe (piège P4).

**Checkpoint** : complétion et couverture disponibles. Un commit.

---

## Phase 10: User Story 8 - Tests à la demande sur GitHub (Priority: P3)

**But** : un workflow GitHub existe ; il se lance à la main seulement.

**Test indépendant** : `grep -c "workflow_dispatch" .github/workflows/tests.yml` rend `1` ; `grep -cE '^[[:space:]]*(push|pull_request|schedule):' .github/workflows/tests.yml` rend `0`.

### Implementation for User Story 8

- [ ] T031 [US8] Créer `.github/workflows/tests.yml` à partir du gabarit (fiche T031). Résultat : `OK T031 : 1 fichier(s) écrit(s).`
- [ ] T032 [US8] Contrôler l'absence de déclencheur automatique et committer `.github/workflows/tests.yml` (fiche T032). Résultat : `1`, puis `0` ; commit `ci(155): Ajouter les tests à la demande sur GitHub`. Ne lance jamais le workflow.

**Checkpoint** : workflow présent, jamais lancé. Un commit.

---

## Phase 11: User Story 9 - Un premier extrait du plus gros fichier (Priority: P3)

**But** : `ReplayableSnapshotProvider` a son propre fichier ; le code déplacé ne change pas.

**Test indépendant** : `wc -l Sources/RoadieDaemon/LayoutMaintainer.swift` rend `4392`.

### Implementation for User Story 9

- [ ] T033 [US9] Déplacer la classe vers `Sources/RoadieDaemon/ReplayableSnapshotProvider.swift` avec `specs/155-consolidation-projet/tools/extraire_fournisseur.py` (fiche T033). Résultat : `lignes_deplacees=69` ; `lignes_restantes=4392` ; le contrôle `--check` rend `OK`. Ne lance pas l'outil deux fois : la fiche a un garde `test -e`.
- [ ] T034 [US9] Lancer la suite complète et committer `Sources/RoadieDaemon/LayoutMaintainer.swift` et `Sources/RoadieDaemon/ReplayableSnapshotProvider.swift` (fiche T034). Résultat : suite `exit=0`, 2533 tests dans 386 suites ; commit `refactor(155): Sortir ReplayableSnapshotProvider de LayoutMaintainer`.

**Checkpoint** : le plus gros fichier a 70 lignes de moins. Un commit.

---

## Phase 12: User Story 10 - Savoir si une version plus récente existe (Priority: P3)

**But** : `roadie update check` dit si une version plus récente est publiée. C'est le seul appel réseau de Roadie.

**Test indépendant** : `.build/debug/roadie update check` répond en 6 secondes au plus, avec le code 0 ou 1.

### Decision and Tests for User Story 10 (décision et tests écrits avant le code)

- [ ] T035 [US10] Créer `docs/decisions/031-premier-appel-reseau.md` à partir du gabarit (fiche T035). Résultat : `OK T035 : 1 fichier(s) écrit(s).`
- [ ] T036 [US10] Créer `Tests/RoadieDaemonTests/Spec155ReleaseCheckTests.swift` à partir du gabarit (fiche T036). Résultat : `OK T036 : 1 fichier(s) écrit(s).` Ne lance pas les tests : la compilation échoue jusqu'à la fin de T037, c'est attendu.

### Implementation for User Story 10

- [ ] T037 [US10] Créer `Sources/RoadieDaemon/ReleaseCheck.swift` à partir du gabarit (fiche T037). Résultat : `OK T037 : 1 fichier(s) écrit(s).`
- [ ] T038 [US10] Brancher la commande `update check` dans `Sources/RoadieDaemon/CLICommandRouter.swift` (fiche T038). Résultat : `./scripts/test --no-parallel --filter Spec155ReleaseCheckTests` affiche `Test run with 5 tests in 1 suite passed`. Cette tâche exige T027.
- [ ] T039 [US10] Documenter `roadie update check` dans `docs/fr/cli.md`, `docs/en/cli.md` et `CHANGELOG.md` (fiche T039). Résultat : `OK T039 : 3 fichier(s) écrit(s).`
- [ ] T040 [US10] Faire un seul appel réel, lancer la suite complète et committer (fiche T040). Résultat : réponse en 6 secondes au plus, `code=0` ou `code=1`, puis `usage=64` ; suite `exit=0`, 2538 tests dans 387 suites ; commit `feat(155): Ajouter roadie update check`.

**Checkpoint** : la vérification de version existe. Un commit.

---

## Phase 13: User Story 11 - Inventaire des images et preuves publiées (Priority: P3)

**But** : lister les images et diaporamas visibles sur le dépôt public. Aucun fichier n'est retiré.

**Test indépendant** : `specs/155-consolidation-projet/validation/inventaire-publications.md` existe et liste 26 images et 21 diaporamas.

### Implementation for User Story 11

- [ ] T041 [US11] Produire `specs/155-consolidation-projet/validation/inventaire-publications.md` avec `specs/155-consolidation-projet/tools/inventaire.py` (fiche T041). Résultat : `OK : 26 image(s) et 21 diaporama(s) listés dans …`. Ne retire et ne modifie aucune image.
- [ ] T042 [US11] Committer `specs/155-consolidation-projet/validation/inventaire-publications.md` (fiche T042). Résultat : commit `docs(155): Inventorier les images et diaporamas publiés`.

**Checkpoint** : l'inventaire attend la décision de l'utilisateur (`decisions.md` D8). Un commit.

---

## Phase 14: Polish & Cross-Cutting Concerns

**But** : contrôle final sur l'état complet, reçu de validation, journal.

- [ ] T043 Relancer la suite complète et les tests des scripts (fiche T043). Résultat : `./scripts/test --no-parallel` rend `exit=0`, 2538 tests dans 387 suites ; `python3 -I -B -m unittest discover -s scripts/tests` rend `Ran 28 tests` puis `OK`.
- [ ] T044 Créer `specs/155-consolidation-projet/validation.md` à partir du gabarit et y écrire la valeur observée de chaque critère SC-001 à SC-013 et de l'exigence FR-021 (fiche T044). Résultat : `grep -c "À REMPLIR" specs/155-consolidation-projet/validation.md` rend `0`. Une valeur non observée s'écrit « non vérifié » avec la raison.
- [ ] T045 Ajouter le bilan de la session à la fin de `.specify/memory/sessions/journal.md` et faire le dernier commit (fiche T045). Résultat : commit `docs(155): Consigner la validation de la consolidation` ; `git status --short` n'affiche rien.

---

## Hors tâches

Ces actions ne font pas partie du travail. Ne les fais pas, même si elles semblent utiles.

- Pousser la branche, fusionner dans `main`, publier une release.
- Installer Roadie (`make install`, `scripts/install`) ou redémarrer le service.
- Lancer le workflow GitHub (`decisions.md` D5).
- Retirer ou modifier une image, une capture ou un diaporama (`decisions.md` D8).
- Découper davantage `LayoutMaintainer.swift`, ajouter la complétion bash ou fish, ajouter une mise à jour automatique.
- Corriger un défaut hors de la spec 155. Note-le dans ton compte rendu.
- Nettoyer le worktree ou supprimer `.build`.

## Dependencies & Execution Order

### Ordre des phases

Ordre strict : Phase 1, puis les phases 3 à 13 dans l'ordre, puis la phase 14.
La phase 2 est vide.

### Dépendances entre stories

| Tâche | Exige | Raison |
|-------|-------|--------|
| T003 (remplacement du titre) | le `git mv` de la même fiche | le fichier `030-…` doit exister |
| T017 | T016 | les sections s'ajoutent au fichier déjà allégé |
| T028 | T004 | les deux tâches modifient `.gitignore` ; T028 s'appuie sur le texte laissé par T004 |
| T038 | T027 | les deux tâches modifient `CLICommandRouter.swift` ; T038 s'appuie sur le texte laissé par T027 |
| T044 | T043 | le reçu reprend les résultats du contrôle final |

Les autres stories ne dépendent pas les unes des autres pour leur code. L'ordre reste
imposé pour deux raisons. Un : chaque commit exige un `git status --short` vide, donc une
story non terminée bloque le commit de la suivante. Deux : les nombres de tests attendus à
chaque contrôle dépendent de l'ordre. Après un arrêt (règle R0), aucune story ne continue.

Nombres mesurés le 10 novembre 2026 (`research.md` R16) :

| Après | Tests | Suites |
|-------|------:|-------:|
| T001 (base) | 2523 | 383 |
| T012 (US2) | 2527 | 384 |
| T015 (US3) | 2529 | 385 |
| T021 (US5) | 2529 | 385 |
| T024 (US6) | 2529 | 385 |
| T030 (US7) | 2533 | 386 |
| T034 (US9) | 2533 | 386 |
| T040 (US10) | 2538 | 387 |
| T043 (final) | 2538 | 387 |

### Dans une story

- Les tests sont créés avant le code quand la fiche le dit (T006, T025, T036). Ils ne compilent pas tant que le code manque : ne les lance pas avant la tâche indiquée.
- La dernière tâche de la story contrôle, puis committe. Pas de commit avant.

## Traçabilité des exigences

Ce tableau sert au contrôle. Il ne change ni l'ordre ni le contenu des tâches.

| Exigence (`spec.md`) | Tâches | Contrôle |
|----------------------|--------|----------|
| FR-001 | T002 | `grep -c "/Users/moi"` rend `0` (T002) |
| FR-002 | T003 | un seul fichier `013-` (T003) |
| FR-003 | T004 | `git ls-files` sans `bak-` (T004) |
| FR-004 | T010 | `0.13.0` dans un seul fichier (T010) |
| FR-005 | T009, T010, T012 | commit lu dans le bundle temporaire (T012). Le suffixe `-dirty` est écrit par T010 ; aucune commande ne le contrôle. |
| FR-006 | T008, T012 | `roadied 0.13.0 (abc12345)` (T012) |
| FR-007 | T006, T007, T011 | 4 tests de `Spec155BuildIdentityTests` (T008) |
| FR-008 | T012 | test existant de `roadie --version` dans la suite complète (T012) |
| FR-009 | T013, T014 | 2 tests de `Spec155ConfigGuardTests` (T014) |
| FR-010 | T014 | 2 tests de `Spec155ConfigGuardTests` (T014) |
| FR-011 | T015 | fichier `docs/dev/ajouter-un-reglage.md` créé (T015) |
| FR-012 | T016, T017, T018 | 366 lignes déplacées (T016) ; taille et marqueurs (T018) |
| FR-013 | T017 | section « Pièges connus » (T017, T018) |
| FR-014 | T019, T020, T021 | `grep -c "CFGetTypeID"` rend `5` (T021) |
| FR-015 | T022, T023, T024 | recherche vide, `rc=1` (T024) |
| FR-016 | T025, T026, T027, T030 | 4 tests de `Spec155ShellCompletionTests` (T027) ; `zsh=0`, `bash=64` (T030) |
| FR-017 | T028, T030 | `coverage=0` et une ligne `coverage : lignes …` (T030) |
| FR-018 | T031, T032 | `1`, puis `0` (T032) |
| FR-019 | T033, T034 | contrôle `--check` (T033) ; suite complète (T034) |
| FR-020 | T035, T036, T037, T038, T040 | 5 tests de `Spec155ReleaseCheckTests` (T038) ; appel réel (T040) |
| FR-021 | T037, T044 | `grep -rl "URLSession" Sources` rend un seul fichier (T044) |
| FR-022 | T041, T042 | rapport produit, aucune image retirée (T041) |
| FR-023 | T011, T021, T024, T029, T039 | fichiers écrits par chaque fiche |
| FR-024 | toutes | `quickstart.md` section 8 ; ligne SC-013 de `validation.md` (T044) |

## Parallel Example

Aucun. Un seul implémenteur, un seul worktree, aucune tâche `[P]`.
Deux suites de tests lancées en même temps se gênent : ne lance jamais deux commandes de test à la fois.

## Implementation Strategy

### MVP (US1 seule)

1. T001, puis T002 à T005.
2. Arrêt possible : la documentation publique est propre, un commit.

### Livraison par incréments

Chaque phase laisse le projet compilable et testé, avec un commit local. Un arrêt après
n'importe quel « Checkpoint » laisse un état cohérent. Reprise : première tâche non cochée.

### Compte rendu de fin

Donne : la dernière tâche cochée, le résultat de T043, le contenu de `validation.md`, les
écarts de nombres de tests s'il y en a, et toute application de la règle R0.

## Notes

- 45 tâches, 13 commits locaux. Aucun push.
- Les messages de commit sont écrits dans les fiches. Copie-les tels quels.
- Un échec isolé du test `Spec151ModifierGestureTests.aNewGenerationNeverRestoresAnObsoleteLayout` : piège P3 (relance ce test seul).
- Décisions en attente de l'utilisateur : `decisions.md`, D1 à D5 et D8. Elles ne bloquent aucune tâche.
