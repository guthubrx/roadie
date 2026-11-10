# Validation - 155 consolidation du projet

Remplace chaque `À REMPLIR` par la valeur observée (tâche T044). N'écris jamais une valeur
non observée : écris « non vérifié » et la raison.

## Résultats

| Critère | Commande | Attendu | Observé |
|---------|----------|---------|---------|
| SC-001 | `grep -c "/Users/moi" README.md README.fr.md` | `README.md:0` et `README.fr.md:0` | À REMPLIR |
| SC-002 | `grep -rn '"0\.13\.0"' Sources scripts` | 1 ligne, dans `Sources/RoadieDaemon/DaemonHealth.swift` | À REMPLIR |
| SC-003 | bundle temporaire de T012, `plutil -extract RoadieBuildCommit raw …` | le commit court | À REMPLIR |
| SC-004 | `./scripts/test --no-parallel --filter Spec155ConfigGuardTests` | 2 tests réussis | À REMPLIR |
| SC-005 | `wc -c AGENTS.md` | moins de 8 000 | À REMPLIR |
| SC-006 | `grep -c "CFGetTypeID" Sources/RoadieDaemon/AppTargetQueryService.swift` | 5 (2 avant la tâche T019) | À REMPLIR |
| SC-007 | `grep -rn "drag.real_press\|drag.real_router_press" Sources/` | aucune ligne | À REMPLIR |
| SC-008 | `.build/debug/roadie completion zsh \| zsh -n ; echo $?` | 0 | À REMPLIR |
| SC-009 | `make coverage ; echo $?` | une ligne `coverage : lignes …`, puis 0 | À REMPLIR |
| SC-010 | `time .build/debug/roadie update check` | réponse en 6 s au plus, code 0 ou 1 | À REMPLIR |
| SC-011 | `wc -l Sources/RoadieDaemon/LayoutMaintainer.swift` | au plus 4 400 (attendu : 4 392) | À REMPLIR |
| SC-012 | `./scripts/test --no-parallel` | 2 538 tests / 387 suites, code 0 | À REMPLIR |
| SC-012 | `python3 -I -B -m unittest discover -s scripts/tests` | 28 tests, `OK` | À REMPLIR |
| SC-013 | relecture des commandes lancées | aucun push, aucune publication, aucune dépense | À REMPLIR |

## Tâches non terminées

À REMPLIR : « aucune », ou une ligne par tâche avec la commande lancée et l'erreur exacte.

## Non vérifié

- Installation réelle (`make install`) : hors tâches. `roadied --version` de l'application
  installée n'a donc pas été relu.
- Workflow GitHub : jamais lancé (décision D5 de `decisions.md`).
- Complétion dans un terminal interactif (Tab) : seul `zsh -n` est vérifié.
- À REMPLIR : tout autre point non vérifié, ou « rien d'autre ».

## Décisions en attente de l'utilisateur

Voir `specs/155-consolidation-projet/decisions.md` : D1 à D5 et D8.
