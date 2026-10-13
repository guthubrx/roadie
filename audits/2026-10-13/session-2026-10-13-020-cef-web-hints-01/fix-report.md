# Rapport des cycles de correction

## Résumé
- Findings sélectionnés  : 1 (seul CRITICAL/HIGH)
- Findings corrigés      : 1
- Findings bloqués       : 0
- Findings non traités   : 3 (MEDIUM/LOW, hors sélection 9.1 ou choix de conception)

## Détail

### Fixed (vérification OK, sans commit)
| Finding | Titre | Commit SHA | Effort réel |
|---|---|---|---|
| PERF-001 | Recherche linéaire dans `unexplored` pour chaque élément en attente | aucun (consigne) | XS |

Fichiers modifiés :
- `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/020-cef-web-hints/Sources/RoadieDaemon/AppTargetQueryService.swift` : `focusableLeaves` indexe les ancêtres des chemins restés dans la pile dans `containers` (O(m + p + u * d)) ; commentaires de complexité de `focusableLeaves` et `scan` mis à jour.
- `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/020-cef-web-hints/Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift` : une expectation (descendant profond resté dans la pile ; `0.10.0` n'est pas sous `0.1`).

Tests : `./scripts/test` 833 tests, 90 suites, exit 0 avant ; exit 0 après correction ; exit 0 après ajout de l'expectation.

### Non traités
| Finding | Raison |
|---|---|
| QUAL-001 | MEDIUM, extraction de fonction = choix de structure |
| OBS-001 | LOW, sémantique de `focusableAdded` à trancher |
| MIN-001 | LOW |

## Incident
Pendant l'audit, un autre agent a ajouté puis retiré un bloc jetable `FORENSIC-020c` dans `scan()` (07:20-07:21 CEST). La correction PERF-001 touche une autre zone et s'est appliquée proprement. Les tests ont été relancés sur l'état final, sans le bloc.

## Prochaine action
- Committer PERF-001 avec le reste de la branche (décision utilisateur).
- Trancher OBS-001 et QUAL-001.
