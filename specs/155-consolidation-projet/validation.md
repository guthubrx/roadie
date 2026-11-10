# Validation - 155 consolidation du projet

Remplace chaque champ marqué « à remplir » (écrit en majuscules ci-dessous) par la valeur
observée (tâche T044). N'écris jamais une valeur non observée : écris « non vérifié » et la raison.

## Résultats

| Critère | Commande | Attendu | Observé |
|---------|----------|---------|---------|
| SC-001 | `grep -c "/Users/moi" README.md README.fr.md` | `README.md:0` et `README.fr.md:0` | README.md:0 et README.fr.md:0 |
| SC-002 | `grep -rl '0\.13\.0' Sources scripts` | 1 seul fichier : `Sources/RoadieDaemon/DaemonHealth.swift` (2 fichiers avant la tâche T010) | 1 fichier, DaemonHealth.swift |
| SC-003 | bundle temporaire de T012, `plutil -extract RoadieBuildCommit raw …` | le commit court | abc12345 ; roadied 0.13.0 (abc12345) |
| SC-004 | `./scripts/test --no-parallel --filter Spec155ConfigGuardTests` | 2 tests réussis | 2 tests réussis |
| SC-005 | `wc -c AGENTS.md` | moins de 8 000 | 3736 octets ; 366 lignes conservées |
| SC-006 | `grep -c "CFGetTypeID" Sources/RoadieDaemon/AppTargetQueryService.swift` | 5 (2 avant la tâche T019) | 5 contrôles CFGetTypeID |
| SC-007 | `grep -rn "drag.real_press\|drag.real_router_press" Sources/` | aucune ligne | 0 occurrence |
| SC-008 | `.build/debug/roadie completion zsh \| zsh -n ; echo $?` | 0 | 0 |
| SC-009 | `make coverage ; echo $?` | une ligne `coverage : lignes …`, puis 0 | 71,30 % lignes ; 68,51 % fonctions ; 64,64 % régions ; code 0 |
| SC-010 | `time .build/debug/roadie update check` | réponse en 6 s au plus, code 0 ou 1 | GitHub : à jour, code 0, 0,320 s |
| SC-011 | `wc -l Sources/RoadieDaemon/LayoutMaintainer.swift` | au plus 4 400 (attendu : 4 392) | 4392 lignes, 69 lignes déplacées sans changement |
| SC-012 | `./scripts/test --no-parallel` | 2 538 tests / 387 suites, code 0 | 2538 tests / 387 suites, code 0 |
| SC-012 | `python3 -I -B -m unittest discover -s scripts/tests` | 28 tests, `OK` | 28 tests, OK |
| SC-013 | relecture des commandes lancées | aucune CI ni dépense ; publication autorisée après les gates | Aucune dépense, aucune CI ; publication à venir selon reprise |
| FR-021 | `grep -rl "URLSession" Sources` | 1 seul fichier : `Sources/RoadieDaemon/ReleaseCheck.swift` | ReleaseCheck.swift uniquement |

## Tâches non terminées

Aucune tâche préparatoire T001–T045 ouverte ; reprise T046–T053 en cours.

## Non vérifié

- Installation réelle (`make install`) : hors tâches. `roadied --version` de l'application
  installée n'a donc pas été relu.
- Workflow GitHub : jamais lancé (décision D5 de `decisions.md`).
- Complétion dans un terminal interactif (Tab) : seul `zsh -n` est vérifié.
- Pas d’essai Tab dans un terminal interactif ; syntaxe et sortie du routeur vérifiées.

## Décisions en attente de l'utilisateur

Voir `specs/155-consolidation-projet/decisions.md` : D1 à D5 et D8.

## Reprise du 10 novembre

Les mentions « hors tâches » ci-dessus appartiennent à la préparation. Installation et
publication sont maintenant autorisées et seront vérifiées avant clôture.

## Compléments vérifiés avant audit

- Licence Apache-2.0 officielle et notices TOMLKit/toml++ intégrées au bundle.
- 26 tests ciblés de 155 ; 29 tests de scripts (dont clean/dirty suivi/dirty non suivi).
- 7 tests Launcher, cas avant en échec puis après réussi ; édition réelle du fichier en test.
- Contrôle des 20 modifications de réglages conservé et réussi après correction des commentaires.
- CI YAML relue : workflow_dispatch seul, contents:read et checkout SHA épinglé, jamais exécutée.
- 21 diaporamas retirés après archive SHA-256 ; 26 images gardées, dont les deux preuves liées à l'audit 131.
- Convergence du code : CONVERGED, un passage, aucune tâche ajoutée ; détails dans validation/convergence.md.
- Une suite complète a rencontré le test intermittent Spec151 ; 19 tests de recontrôle isolé passent.

Les opérations de publication et d'installation restent en cours (T053).

## Audit V15 du code

Révision 1 : decision=pass, release_blocked=false, 14/14 contrôles, aucun finding ouvert.
Correction : référence checkout du gabarit/recette épinglée. Historique entier : 18 alertes
réfutées par égalité SHA-256 avec les fichiers source historiques ; aucune exception de scanner.
Build Release réussi dans le runner (266,935 s). Validation déterministe de l'audit réussie.
Deux passages de convergence, aucun manque de code nouveau. La revue du commit exact suit
l'audit local car Bridget exige un commit pour la vue immuable ; intégration et publication
restent suspendues à cette revue. La qualification du runtime de 0.14.0 reste T053.

Dernière suite complète : 2549 tests / 388 suites, code 0, 81,709 s.
Rapport d'audit : audits/2026-11-10/session-2026-11-10-consolidation-155-01/.
Le verdict A/100 de grade.json mesure les défauts ouverts et la décision du gate ;
il ne remplace pas les notes de qualité par axe (56–75/100 avant activation).
Les 42 justifications et limites sont conservées dans axis-scoring.md.
