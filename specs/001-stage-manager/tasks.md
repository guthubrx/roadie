---
description: "Tâches d'implémentation — Stage Manager Suckless"
---

# Tasks: Stage Manager Suckless

**Input** : Design documents in `/specs/001-stage-manager/`
**Prerequisites** : plan.md (required), spec.md (3 user stories), research.md (D1-D9), data-model.md (WindowRef, Stage, CurrentStage), contracts/cli-contract.md
**Tests** : INCLUS — la spec exige des tests d'acceptation shell (cf. research.md D8 et FR-008)
**Organization** : tâches groupées par user story

## Format

`- [ ] T### [P?] [USx?] Description avec chemin de fichier`

- **[P]** : parallélisable (fichier différent, pas de dépendance amont incomplète)
- **[USx]** : user story (US1 = bascule, US2 = assignation, US3 = tolérance disparition)

## Path Conventions

- Code source : `stage.swift` (mono-fichier à la racine, principe A constitution)
- Build : `Makefile` à la racine
- Tests d'acceptation : `tests/*.sh`
- Tous les chemins sont relatifs à la racine du worktree `<repo-root>/.worktrees/001-stage-manager/`

---

## Phase 1: Setup

**Purpose** : initialiser la structure projet minimale.

- [X] T001 Créer le squelette `stage.swift` à la racine avec uniquement les imports requis (`import Cocoa`, `import ApplicationServices`, `import CoreGraphics`) et un `main()` qui exit 0
- [X] T002 [P] Créer le `Makefile` à la racine avec cibles `all`, `install`, `clean`, `test` (cf. research.md D9 pour le contenu attendu)
- [X] T003 [P] Créer `tests/helpers.sh` avec fonctions `setup_stage_dir`, `cleanup_stage_dir`, `open_terminal`, `close_terminal`, `assert_file_contains`, `assert_file_lines`
- [X] T004 [P] Créer `README.md` à la racine pointant vers `specs/001-stage-manager/quickstart.md`
- [X] T005 Vérifier que `make` produit un binaire `stage` exécutable (sans logique métier encore, juste exit 0)

**Checkpoint** : projet compile, structure de fichiers en place.

---

## Phase 2: Foundational

**Purpose** : briques transversales utilisées par les 3 user stories. Aucune story ne peut démarrer sans cette phase.

**⚠️ CRITICAL** : aucune user story ne peut commencer avant la fin de cette phase.

- [X] T006 Déclarer la fonction privée `_AXUIElementGetWindow` dans `stage.swift` via `@_silgen_name` (cf. research.md D2 pour la déclaration exacte)
- [X] T007 Implémenter dans `stage.swift` la fonction `checkAccessibility() -> Never?` qui appelle `AXIsProcessTrusted()` et exit 2 avec le message exact spécifié (cf. research.md D6 et contracts/cli-contract.md)
- [X] T008 [P] Implémenter dans `stage.swift` les fonctions de persistance : `stagePath(_ N: Int) -> String`, `currentPath() -> String`, `readStage(_ N: Int) -> [WindowRef]`, `writeStage(_ N: Int, _ refs: [WindowRef])`, `readCurrent() -> Int`, `writeCurrent(_ N: Int)` (cf. data-model.md sections Stage et CurrentStage)
- [X] T009 [P] Implémenter dans `stage.swift` la struct `WindowRef` avec champs `pid: pid_t, bundleID: String, cgWindowID: CGWindowID`, méthodes `serialize() -> String` et `static parse(_ line: String) -> WindowRef?` (parsing TAB ; ligne malformée → nil + log stderr ; cf. data-model.md WindowRef Validation)
- [X] T010 Implémenter dans `stage.swift` la fonction `printUsageAndExit() -> Never` qui imprime la ligne d'usage exacte sur stderr et exit 64 (cf. contracts/cli-contract.md "Sans argument ou avec un argument inconnu")
- [X] T011 Implémenter dans `stage.swift` le routage CLI dans `main()` : parse `CommandLine.arguments`, dispatch vers `cmdSwitch(N)` ou `cmdAssign(N)`, sinon `printUsageAndExit()`. Les corps `cmdSwitch` et `cmdAssign` peuvent être stubés pour cette phase.
- [X] T012 [P] Écrire `tests/01-permission.sh` comme **test manuel** (NON inclus dans `make test`) : documente la procédure pour révoquer la permission Accessibility dans Réglages Système, exécute `./stage 1` après révocation, vérifie exit code 2 + message stderr exact. Exclu de l'exécution automatisée car la révocation Accessibility ne peut pas être scriptée sans privilèges root et désactivation TCC. (couvre FR-007, FR-008, edge case "Aucune permission Accessibility")
- [X] T013 [P] Écrire `tests/05-corrupt.sh` qui couvre 2 scénarios : (a) `~/.stage/1` contient une ligne malformée + des lignes valides → vérifier ignore + log stderr + traitement des valides ; (b) édition manuelle simulée : ajouter une `WindowRef` valide en bas du fichier via `printf >>`, exécuter `./stage 1`, vérifier que la fenêtre correspondante est dé-minimisée comme les autres (couvre edge case "Fichier d'état corrompu" + FR-011 "édition manuelle respectée")

**Checkpoint** : permission validée, persistance fonctionnelle, parser robuste, CLI dispatch en place. Les 3 user stories peuvent démarrer.

---

## Phase 3: User Story 1 — Bascule entre 2 stages (Priority: P1) 🎯 MVP

**Goal** : permettre à l'utilisateur de taper `stage 1` ou `stage 2` pour faire disparaître les fenêtres d'un groupe et apparaître celles de l'autre.

**Independent Test** : préremplir manuellement `~/.stage/1` et `~/.stage/2` avec deux fenêtres connues (Terminal et TextEdit), exécuter `./stage 1` puis `./stage 2`, vérifier visuellement la minimisation et restauration via `osascript`.

- [X] T014 [US1] Implémenter dans `stage.swift` la fonction `liveCGWindowIDs() -> Set<CGWindowID>` qui appelle `CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)` et collecte tous les `kCGWindowNumber` (cf. research.md D4 et FR-006)
- [X] T015 [US1] Implémenter dans `stage.swift` la fonction `findAXWindow(pid: pid_t, target: CGWindowID) -> AXUIElement?` qui itère les fenêtres AX de l'app jusqu'à matcher (cf. research.md D4 pseudo-code)
- [X] T016 [US1] Implémenter dans `stage.swift` la fonction `setMinimized(_ window: AXUIElement, _ value: Bool) -> AXError` (cf. research.md D1)
- [X] T017 [US1] Implémenter dans `stage.swift` la fonction `pruneDeadRefs(_ N: Int, _ alive: Set<CGWindowID>) -> Int` qui filtre `readStage(N)`, écrit le résultat avec `writeStage(N, ...)`, log sur stderr chaque ID retiré (cf. data-model.md `Stage.prune` et FR-006)
- [X] T018 [US1] Implémenter dans `stage.swift` la fonction `cmdSwitch(_ N: Int) -> Never` qui : (1) appelle `pruneDeadRefs` sur tous les stages, (2) pour chaque ref de stage ≠ N appelle `setMinimized(true)`, (3) pour chaque ref de stage == N appelle `setMinimized(false)`, (4) appelle `writeCurrent(N)`, (5) exit 0 ou 1 selon erreurs AX (cf. contracts/cli-contract.md `stage <N>`)
- [X] T019 [US1] Brancher `cmdSwitch` dans le dispatch CLI de `main()` (le stub posé en T011 est remplacé)
- [X] T020 [US1] Écrire `tests/03-switch.sh` qui : ouvre 2 fenêtres Terminal via `osascript`, capture leurs positions/tailles initiales (`bounds` AX), popule manuellement `~/.stage/1` et `~/.stage/2` avec leurs `WindowRef`, exécute `./stage 1`, vérifie via `osascript` que la fenêtre du stage 2 est minimisée et celle du stage 1 visible, idem inverse, et **assertion supplémentaire** : après le retour à un stage, vérifier que les positions/tailles des fenêtres restaurées sont identiques aux positions initiales capturées (couvre US1 acceptance scenarios 1 et 2 + FR-012 "jamais modifier position/taille/ordre Z")
- [X] T021 [US1] Étendre `tests/03-switch.sh` avec scénario "stage vide" : vider `~/.stage/2`, exécuter `./stage 2`, vérifier que toutes les fenêtres du stage 1 sont minimisées (couvre US1 acceptance scenario 3)

**Checkpoint** : `stage 1` et `stage 2` basculent correctement avec stages préremplis. Le binaire est utilisable manuellement (édition vi des fichiers d'état). MVP partiel.

---

## Phase 4: User Story 2 — Assigner la fenêtre frontmost (Priority: P1)

**Goal** : permettre à l'utilisateur de taper `stage assign 1` ou `stage assign 2` pour rattacher la fenêtre actuellement au premier plan à un stage.

**Independent Test** : ouvrir une fenêtre Terminal au premier plan, exécuter `./stage assign 1`, vérifier `cat ~/.stage/1` contient une ligne avec le `pid` de cette fenêtre.

- [X] T022 [US2] Implémenter dans `stage.swift` la fonction `frontmostWindowRef() -> WindowRef?` qui : (1) `NSWorkspace.shared.frontmostApplication`, (2) `AXUIElementCreateApplication(pid)`, (3) `AXUIElementCopyAttributeValue(_, kAXFocusedWindowAttribute, _)`, (4) `_AXUIElementGetWindow(focused, _)`, (5) retourne `WindowRef(pid, bundleID, cgWindowID)` ou `nil` avec log stderr explicite si étape échoue (cf. research.md D3, FR-008, edge case "Aucun focus")
- [X] T023 [US2] Implémenter dans `stage.swift` la fonction `cmdAssign(_ N: Int) -> Never` qui : (1) crée `~/.stage/` (mode 0755) si absent, (2) appelle `frontmostWindowRef()`, (3) retire la ref des autres stages via `removeFromAllStages(cgWindowID:)`, (4) ajoute au stage `N` via `addToStage(N, ref)`, (5) exit 0 ou 1 (cf. contracts/cli-contract.md `stage assign <N>`)
- [X] T024 [US2] Implémenter les helpers `removeFromAllStages(_ wid: CGWindowID)` et `addToStage(_ N: Int, _ ref: WindowRef)` dans `stage.swift` (cf. data-model.md Stage.add et Stage.remove)
- [X] T025 [US2] Brancher `cmdAssign` dans le dispatch CLI (remplace le stub T011)
- [X] T026 [US2] Écrire `tests/02-assign.sh` qui : ouvre une fenêtre Terminal via `osascript`, l'amène au premier plan, exécute `./stage assign 1`, vérifie que `~/.stage/1` contient exactement 1 ligne avec le bon `pid` et `bundleID = com.apple.Terminal` (couvre US2 acceptance scenario 1)
- [X] T027 [US2] Étendre `tests/02-assign.sh` avec scénario "ré-assignation" : `stage assign 2` sur la même fenêtre, vérifier que `~/.stage/1` est vide et `~/.stage/2` contient la ligne (couvre US2 acceptance scenario 2)
- [X] T028 [US2] Étendre `tests/02-assign.sh` avec scénario "pas de focus" : minimiser toutes les fenêtres, exécuter `./stage assign 1`, vérifier exit 1 et message stderr explicite, vérifier que `~/.stage/` n'a pas été modifié (couvre US2 acceptance scenario 3)

**Checkpoint** : MVP complet. L'utilisateur peut configurer ses stages depuis zéro et basculer entre eux sans toucher manuellement aux fichiers.

---

## Phase 5: User Story 3 — Tolérance aux fenêtres disparues (Priority: P2)

**Goal** : garantir que la fermeture d'applications ne fait pas planter ni dégrader silencieusement l'outil.

**Independent Test** : préremplir un stage avec 3 fenêtres (Terminal, TextEdit, Safari), fermer Safari, exécuter `./stage 1`, vérifier que les 2 fenêtres restantes sont restaurées, qu'un message stderr signale la fenêtre prunée, et que `~/.stage/1` ne contient plus que 2 lignes.

- [X] T029 [US3] Vérifier que la fonction `pruneDeadRefs` (T017) émet bien un message stderr explicite par ID retiré au format `stage : window <wid> from stage <N> no longer exists, pruned` (cf. contracts/cli-contract.md "Sortie erreur")
- [X] T030 [US3] Vérifier que `cmdSwitch` (T018) appelle `pruneDeadRefs` AVANT la phase de minimisation/restauration, pour que les références mortes ne soient pas tentées (et pollueraient stderr avec des AXErrors)
- [X] T031 [US3] Écrire `tests/04-disappeared.sh` qui : ouvre 3 fenêtres (2 Terminal, 1 TextEdit), peuple `~/.stage/1` avec leurs refs, ferme la fenêtre TextEdit, exécute `./stage 1`, vérifie : exit 0, stderr contient le message de prune, `~/.stage/1` ne contient plus que 2 lignes, les 2 fenêtres restantes sont visibles (couvre US3 acceptance scenario 1)
- [X] T032 [US3] Étendre `tests/04-disappeared.sh` avec scénario "stage entièrement mort" : peupler `~/.stage/2` avec 2 refs de fenêtres déjà fermées, exécuter `./stage 2`, vérifier exit 0, stderr signale les 2 prunes, `~/.stage/2` est vide, `~/.stage/current = 2` (couvre US3 acceptance scenario 2)

**Checkpoint** : robustesse temps long acquise. L'outil reste sain après fermetures d'apps.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose** : finitions, vérifications de conformité aux Success Criteria, documentation.

- [X] T033 [P] Mesurer la taille du binaire produit par `make` ; vérifier qu'elle est < 500 KB (SC-003) ; si non, ajuster les flags `swiftc` (`-Osize` au lieu de `-O`) et re-mesurer
- [X] T034 [P] Vérifier l'absence de dépendances non-système avec `otool -L stage` ; toutes les libs listées doivent être dans `/usr/lib/` ou `/System/Library/` (SC-004)
- [X] T035 [P] Vérifier que le code source `stage.swift` ne dépasse pas 200 lignes physiques (cible 150, marge 33%) ; si dépassé, refactorer ou justifier dans `plan.md` Complexity Tracking
- [X] T036 Mesurer les latences réelles : 100 cycles `stage 1` / `stage 2` avec 10 fenêtres par stage, vérifier p95 < 500 ms (SC-001) ; 100 cycles `stage assign 1` avec différentes fenêtres frontmost, vérifier p95 < 200 ms (SC-002)
- [ ] T037 [P] Stress test : 100 cycles de bascule consécutifs ; vérifier zéro plantage et absence de croissance mémoire pathologique via `leaks <pid>` ou simple observation (SC-005)
- [ ] T038 [P] Long-run simulé : créer 20 fenêtres, en assigner 10 à chaque stage, fermer 5 apps aléatoirement, faire 50 bascules, vérifier que les fichiers d'état n'ont aucune ligne morte à la fin (auto-GC effectif sur durée prolongée, couvre SC-006)
- [X] T039 [P] Mettre à jour `README.md` racine pour qu'il pointe vers `specs/001-stage-manager/quickstart.md` et résume en 5 lignes ce qu'est l'outil
- [X] T040 [P] Vérifier que la cible `make test` exécute tous les `tests/*.sh` séquentiellement et exit non-zéro au premier échec (cf. research.md D9)
- [X] T041 Lecture finale du code `stage.swift` : aucune dépendance externe, aucun `(bundleID, title)` comme clé primaire, aucun fallback silencieux, sortie standard silencieuse en succès (relit la constitution projet, principes A→F)

---

## Dependency Graph

```
Phase 1 Setup (T001-T005)
       │
       ▼
Phase 2 Foundational (T006-T013)
       │
       ├──────────────────┬──────────────────┐
       ▼                  ▼                  ▼
Phase 3 US1 (T014-T021)  Phase 4 US2 (T022-T028)  (Phase 5 dépend du code de Phase 3)
       │                  │
       └────────┬─────────┘
                ▼
Phase 5 US3 (T029-T032)  ← réutilise pruneDeadRefs (T017) et cmdSwitch (T018)
                │
                ▼
Phase 6 Polish (T033-T041)
```

**Note** : US1 et US2 sont théoriquement parallélisables (fichiers de tests indépendants, code partagé en Foundational). En pratique, faire US1 d'abord permet de tester US2 visuellement plus facilement.

---

## Parallel Execution Examples

### Phase 1 — fichiers indépendants

```
T002 Makefile          ┐
T003 tests/helpers.sh  ├─ exécutables en parallèle après T001
T004 README.md         ┘
```

### Phase 2 — fonctions disjointes dans stage.swift

```
T008 persistance       ┐
T009 WindowRef parser  ├─ rédigeables en parallèle (touchent stage.swift mais
T012 test 01-perm      │   sections distinctes ; merge facile)
T013 test 05-corrupt   ┘
```

### Phase 6 — vérifications indépendantes

```
T033 taille binaire    ┐
T034 otool -L          ├─ mesures parallèles, aucun effet de bord
T035 LOC count         │
T037 stress test       │
T038 long-run sim      │
T039 README.md         │
T040 make test         ┘
```

---

## Implementation Strategy

### MVP minimum viable

**Fin de Phase 4 (T028)** : l'utilisateur peut faire `stage assign 1`, `stage assign 2`, puis `stage 1` / `stage 2` pour basculer. Sans US3, la fermeture d'une app peut produire des AXErrors disgracieuses sur stderr — mais la bascule fonctionne sur les fenêtres vivantes restantes.

C'est le premier livrable utilisable.

### Incremental delivery

| Étape | Livrable | Tâches |
|---|---|---|
| 1 | Squelette compile, structure prête | T001–T005 |
| 2 | Briques transversales testées | T006–T013 |
| 3 | Bascule fonctionnelle | T014–T021 |
| 4 | MVP complet (assignation + bascule) | T022–T028 |
| 5 | Robuste sur fermetures d'apps | T029–T032 |
| 6 | Conforme aux SC chiffrés | T033–T041 |

### Points de validation utilisateur

- Après T028 : démo manuelle au user, possibilité d'arrêter ici si scope V1 satisfaisant.
- Après T032 : produit propre prêt pour usage quotidien.
- Après T041 : conformité totale aux 7 Success Criteria.

---

## Format Validation

- [x] Toutes les 41 tâches commencent par `- [ ]`
- [x] Toutes ont un Task ID séquentiel `T001` à `T041`
- [x] Tâches Setup (Phase 1) : pas de label `[USx]`
- [x] Tâches Foundational (Phase 2) : pas de label `[USx]`
- [x] Tâches Phase 3 : label `[US1]` présent
- [x] Tâches Phase 4 : label `[US2]` présent
- [x] Tâches Phase 5 : label `[US3]` présent
- [x] Tâches Polish (Phase 6) : pas de label `[USx]`
- [x] Marqueur `[P]` réservé aux tâches sans dépendance amont incomplète et touchant des fichiers différents
- [x] Chemin de fichier explicite dans chaque description (`stage.swift`, `Makefile`, `tests/*.sh`, `README.md`)
- [x] User stories en ordre de priorité spec.md (US1 P1, US2 P1, US3 P2)

---

## Summary

| Métrique | Valeur |
|---|---|
| Total tâches | 41 |
| Phase 1 Setup | 5 (T001-T005) |
| Phase 2 Foundational | 8 (T006-T013) |
| Phase 3 US1 Bascule | 8 (T014-T021) |
| Phase 4 US2 Assignation | 7 (T022-T028) |
| Phase 5 US3 Tolérance | 4 (T029-T032) |
| Phase 6 Polish | 9 (T033-T041) |
| Tâches parallélisables `[P]` | 19 |
| MVP scope suggéré | T001–T028 (fin Phase 4) |
| Tests inclus | 5 fichiers shell (`tests/01` à `tests/05`) |
