# Implementation Plan: Consolidation du projet Roadie

**Branch**: `155-consolidation-projet` | **Date**: 2026-11-10 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/155-consolidation-projet/spec.md`

## Summary

Onze lots indépendants issus de la revue du 10 novembre 2026. Chaque lot est petit et
vérifiable seul. Aucun lot ne change la disposition des fenêtres.

| Lot | Résultat | Fichiers principaux |
|-----|----------|---------------------|
| US1 | Documentation publique propre | `README.fr.md`, `docs/decisions/`, `.gitignore` |
| US2 | Version unique, commit du build visible | `Sources/RoadieDaemon/DaemonHealth.swift`, `Sources/roadied/main.swift`, `scripts/build-app-bundle`, `scripts/install`, `scripts/package-dmg` |
| US3 | Garde-fous des réglages | `Sources/RoadieCore/Config.swift`, 1 fichier de test, `docs/dev/ajouter-un-reglage.md` |
| US4 | `AGENTS.md` court, journal déplacé | `AGENTS.md`, `.specify/memory/sessions/journal.md` |
| US5 | Deux gardes de type | `Sources/RoadieDaemon/AppTargetQueryService.swift` |
| US6 | Deux événements de clic retirés | `Sources/RoadieDaemon/DropPreviewController.swift`, `Sources/RoadieDaemon/RailController.swift` |
| US7 | `roadie completion zsh`, `make coverage` | `Sources/RoadieDaemon/ShellCompletion.swift`, `Sources/RoadieDaemon/CLICommandRouter.swift`, `scripts/coverage`, `Makefile` |
| US8 | Workflow GitHub manuel | `.github/workflows/tests.yml` |
| US9 | Un type sorti du plus gros fichier | `Sources/RoadieDaemon/ReplayableSnapshotProvider.swift` |
| US10 | `roadie update check` | `Sources/RoadieDaemon/ReleaseCheck.swift`, `docs/decisions/031-premier-appel-reseau.md` |
| US11 | Inventaire des images et preuves | `specs/155-consolidation-projet/validation/inventaire-publications.md` |

**Méthode pour l'implémenteur** : `quickstart.md` donne les règles. `tasks.md` donne
l'ordre. `recettes.md` donne, pour chaque tâche, les commandes exactes et le résultat
attendu. Les changements sont déjà préparés : l'outil `tools/appliquer.py` les écrit à
partir de `tools/remplacements.json` et du dossier `gabarits/`. L'implémenteur ne retape
aucun code et ne prend aucune décision de conception. Si un texte « avant » ne se trouve
pas tel quel dans un fichier, l'outil n'écrit rien et l'implémenteur s'arrête (règle R0
de `quickstart.md`).

## Technical Context

**Language/Version**: Swift 6 (swift-tools-version 6.0) ; bash ; Python 3 (tests de
scripts, outil de déplacement du journal) ; zsh (script de complétion généré)

**Primary Dependencies**: TOMLKit (déjà présent). Aucune dépendance ajoutée.
`Foundation.URLSession` pour US10 (bibliothèque du système).

**Storage**: fichiers. Clé `RoadieBuildCommit` dans `Roadie.app/Contents/Info.plist` ;
champ facultatif `buildCommit` dans `~/.roadies/daemon-status.json` ; fichier
`.specify/memory/sessions/journal.md`.

**Testing**: Swift Testing (`@Suite`, `@Test`, `#expect`) lancé par `./scripts/test` ;
`python3 -I -B -m unittest discover -s scripts/tests` pour les scripts.

**Target Platform**: macOS 14 ou plus récent, arm64.

**Project Type**: application de bureau avec daemon (`roadied`) et commande (`roadie`).

**Performance Goals**: aucun objectif nouveau. `roadie update check` répond en 6 s au
plus (délai réseau 5 s, garde 6 s).

**Constraints**: aucune action sortante dans les tâches (pas de push, pas de release, pas
de dépense). Aucune suppression de preuve. Aucun changement du comportement de
disposition. `roadie --version` inchangé.

**Scale/Scope**: 45 tâches, 13 commits locaux ; 5 fichiers créés dans `Sources/`,
`scripts/` et `.github/` ; 4 fichiers de test créés ; 6 documents créés ; 20 fichiers
existants modifiés ; 1 fichier renommé ; 1 fichier retiré du suivi Git. Préparation : 12 copies de gabarits et 42 remplacements exacts.

**Base de référence (mesurée le 10 novembre 2026 sur `0b7de36b`)** : voir `research.md`
R15. La tâche T001 refait cette mesure avant tout changement.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article | Contrôle | Résultat |
|---------|----------|----------|
| I - Langue | Artefacts en français | Conforme |
| III - Cycle SpecKit | spec, plan, audit de l'existant, tâches, analyse | Conforme (arrêt voulu avant Implement) |
| V - Périmètre | Les 15 propositions ont un sort nommé ; aucune tâche hors table | Conforme |
| VII - ADR | ADR 031 pour le premier appel réseau ; ADR 013 en double renuméroté 030 | Conforme |
| XV - Tests avant la suite | Chaque lot finit par une tâche de contrôle puis un commit | Conforme, voir note 1 |
| XVI - Worktree | `.worktrees/155-consolidation-projet` | Conforme |
| XVIII - Complexité | `ShellCompletion.zsh` O(n) annoté ; parcours des clés O(n) annoté ; aucune boucle imbriquée sur une même collection | Conforme |
| XIX - Minimalisme | Aucune dépendance ; aucune abstraction pour moins de 3 usages (D17) ; purge automatique exclue par la mesure (D7) | Conforme, voir « Complexity Tracking » |
| XX - Responsabilité | Extraits compilés et exécutés pendant la préparation ; non-vérifié nommé dans `research.md` | Conforme |
| XX.6 - Confidentialité | US6 retire une donnée d'usage ; US10 n'envoie aucune donnée de l'utilisateur ; US11 ne publie rien | Conforme |
| XXII - Optimisation | Aucun gain de performance revendiqué | Sans objet |
| Oxlint | Pas de JavaScript | Sans objet |
| Preuves visibles | Aucun changement d'interface graphique | Sans objet |

Note 1 : la batterie de l'article XV cite des commandes `pnpm`. L'équivalent du projet
est `./scripts/test` (compilation stricte Swift 6 et tests) et les tests de scripts. Le
projet n'a pas d'outil de lint Swift ; aucun n'est ajouté (D12).

Re-contrôle après conception : aucun écart nouveau.

## Project Structure

### Documentation (this feature)

```text
specs/155-consolidation-projet/
├── spec.md                  # besoin, 11 user stories, FR-001 à FR-024
├── decisions.md             # décisions de l'utilisateur, défauts, exclusions
├── research.md              # mesures et sondes R1 à R16
├── plan.md                  # ce fichier
├── data-model.md            # données ajoutées ou modifiées
├── contracts/
│   ├── cli.md               # sorties et codes de retour des commandes
│   └── build-identity.md    # Info.plist, daemon-status.json, scripts
├── quickstart.md            # règles de l'implémenteur (R0, pièges, interdits)
├── recettes.md              # commandes exactes et résultat attendu, par tâche
├── reuse-audit.md           # audit de l'existant (gate avant tasks)
├── tasks.md                 # liste ordonnée des tâches
├── adversarial-review-codex.md  # contre-revue du plan
├── checklists/requirements.md
├── gabarits/                # fichiers complets copiés par appliquer.py (12)
├── tools/appliquer.py       # applique une tâche préparée, ou contrôle sans écrire
├── tools/remplacements.json # 12 copies et 42 remplacements exacts
├── tools/deplacer_journal.py      # outil à usage unique de T016
├── tools/extraire_fournisseur.py  # outil à usage unique de T033
├── tools/inventaire.py      # outil de T041
└── validation/              # créé par les tâches (T001, T041, T044)
```

### Source Code (repository root)

```text
Sources/
├── RoadieCore/Config.swift                       # US3 : accesseur knownKeys()
├── RoadieDaemon/
│   ├── DaemonHealth.swift                        # US2 : RoadieVersion, DaemonStatus.buildCommit
│   ├── AppTargetQueryService.swift               # US5 : deux gardes de type
│   ├── DropPreviewController.swift               # US6 : retrait de drag.real_press
│   ├── RailController.swift                      # US6 : retrait de drag.real_router_press
│   ├── CLICommandRouter.swift                    # US7, US10 : deux commandes
│   ├── ShellCompletion.swift                     # US7 : créé
│   ├── ReleaseCheck.swift                        # US10 : créé
│   ├── LayoutMaintainer.swift                    # US9 : bloc retiré
│   └── ReplayableSnapshotProvider.swift          # US9 : créé (bloc déplacé)
└── roadied/main.swift                            # US2 : sortie de --version

Tests/RoadieDaemonTests/
├── Spec155BuildIdentityTests.swift               # US2
├── Spec155ConfigGuardTests.swift                 # US3
├── Spec155ShellCompletionTests.swift             # US7
└── Spec155ReleaseCheckTests.swift                # US10

scripts/
├── build-app-bundle                              # US2 : 4e argument facultatif
├── install                                       # US2 : calcul du commit
├── package-dmg                                   # US2 : lecture de la version
└── coverage                                      # US7 : créé

.github/workflows/tests.yml                       # US8 : créé
Makefile                                          # US7 : cible coverage
docs/dev/ajouter-un-reglage.md                    # US3 : créé
docs/decisions/030-native-command-input.md        # US1 : renommé depuis 013
docs/decisions/031-premier-appel-reseau.md        # US10 : créé
docs/fr/cli.md, docs/en/cli.md, CHANGELOG.md      # US2, US6, US7, US10
AGENTS.md, .specify/memory/sessions/journal.md    # US4
```

**Structure Decision**: aucun nouveau module. Les fichiers créés vont dans les dossiers
existants. Les tests suivent la convention du projet `Spec<numéro><Sujet>Tests.swift`
dans `Tests/RoadieDaemonTests/`.

## Décisions de conception

1. **Commit du build lu dans `Info.plist`, pas compilé dans le binaire.** Le binaire reste
   reproductible sans Git. La lecture passe par le fichier, pas par `Bundle.main`, parce
   que `~/.local/bin/roadied` est un lien symbolique (`research.md` R2).
2. **`roadie --version` ne change pas.** Un test existant fixe sa sortie
   (`CLICommandRouterTests.versionPrintsSingleVersionConstant`). Le commit s'affiche par
   `roadied --version` et dans `daemon-status.json`.
3. **Complétion générée depuis `CLICommandRouter.commandTable`.** Une commande ajoutée à
   la table apparaît sans autre code. Deux niveaux seulement (commande, premier mot
   suivant) ; les options ne sont pas proposées.
4. **`roadie update check` s'exécute dans le processus `roadie`.** Le daemon ne fait
   aucun appel réseau. La logique est une fonction pure (`ReleaseCheck.evaluate`) qui
   reçoit la lecture réseau en paramètre ; les tests ne touchent pas au réseau.
5. **`make coverage` ne dépend pas du succès des tests.** Mesure du 10 novembre 2026 :
   sous instrumentation, des tests sensibles au temps échouent, et SwiftPM n'écrit alors
   pas son rapport JSON. Le script `scripts/coverage` fusionne lui-même les relevés et
   affiche le résumé (`research.md` R9). `make test` reste le seul juge du succès des
   tests.
6. **Changements appliqués par des outils fournis**, pas à la main. `appliquer.py` fait
   des remplacements exacts : chaque texte « avant » doit apparaître une seule fois. Il
   contrôle toute la tâche avant d'écrire, donc une tâche n'est jamais écrite à moitié.
   Le journal (366 lignes) est déplacé par `deplacer_journal.py`, qui se vérifie contre
   le commit de base. Raison : l'implémenteur prévu est un modèle moins capable ; un
   texte recopié à la main est la première source d'erreur.
7. **Un commit local par lot**, fichiers nommés, sans `git commit -a`, sans push.

## Ordre et dépendances

- T001 (base de référence) précède tout.
- Les lots US1 à US11 sont indépendants pour le comportement. Ils se font dans l'ordre
  des numéros parce que plusieurs touchent les mêmes fichiers :
  `CLICommandRouter.swift` (US7 puis US10), `CHANGELOG.md` et `docs/*/cli.md` (US2, US6,
  US7, US10), `AGENTS.md` (US4).
- Aucune tâche n'est marquée `[P]` : un seul implémenteur, exécution en série.

## Risques et parades

| Risque | Parade |
|--------|--------|
| Le texte « avant » d'une recette ne correspond plus au fichier | Règle R0 : l'outil n'écrit rien ; arrêt et signalement ; aucune adaptation libre |
| Build de test périmé après changement de `DaemonStatus` ou de `RoadieConfig` (signal 11) | Remède écrit dans `quickstart.md` (piège P1) |
| Une user story dépend d'une story suivante sans le dire | Essai par paliers : la suite complète a tourné à chaque point de commit (`research.md` R16) |
| Tests sensibles au temps en échec sur une machine chargée | T001 fixe la base ; un échec déjà présent dans la base n'est pas imputé au lot ; toujours `--no-parallel` ; relance du test seul (piège P3) |
| Appel réseau refusé (pare-feu, Little Snitch) pendant T040 | Le contrôle réel accepte les deux issues prévues : code 0 avec la version, ou code 1 avec la raison en 6 s au plus |
| Machine GitHub incompatible (version de Swift, pas d'écran) | Non vérifié ; workflow manuel seul ; premier essai par l'utilisateur (D5) |

## Complexity Tracking

| Écart | Pourquoi il est nécessaire | Alternative plus simple rejetée, et pourquoi |
|-------|----------------------------|----------------------------------------------|
| Nouveau script `scripts/coverage` (environ 30 lignes) | SwiftPM n'écrit pas `codecov/*.json` quand un test échoue ; il faut fusionner les relevés et appeler `llvm-cov` | Une ligne dans le `Makefile` : constaté insuffisant, le rapport manque dès qu'un test sensible au temps échoue |
| Premier appel réseau (`URLSession`) | US10 : connaître la dernière version sans ouvrir un navigateur | Sparkle : dépendance, clé de signature, flux à héberger. Aucun appel : l'utilisateur ne sait pas qu'il est en retard |
| `ResultBox` marqué `@unchecked Sendable` (US10) | Attente synchrone d'une réponse `URLSession` dans une commande ; l'accès est protégé par un verrou | `async/await` : `CLICommandRouter.dispatch` est synchrone ; le rendre asynchrone toucherait 79 commandes |
| Lecture directe d'`Info.plist` au lieu de `Bundle.main` | `Bundle.main` rend `nil` quand le binaire est lancé par un lien symbolique (constaté) | `Bundle.main.object(forInfoDictionaryKey:)` : ne fonctionne pas dans le cas réel d'installation |
| Champ `buildCommit` ajouté à un contrat existant (spec 016) | FR-007 : le commit doit être lisible sans lancer de commande | Fichier séparé : un second fichier d'état à garder cohérent |
