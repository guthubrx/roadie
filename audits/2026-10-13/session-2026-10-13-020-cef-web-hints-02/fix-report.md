# Rapport des cycles de correction

## Résumé
- Findings sélectionnés : 2 (sélection élargie aux MEDIUM/LOW non ambigus, consigne de l'appelant)
- Findings corrigés : 2
- Findings bloqués : 0
- Findings non traités : 1 (QUAL-001, choix de structure)

## Détail

### Fixed (vérification OK, sans commit)
| Finding | Titre | Commit SHA | Effort réel |
|---|---|---|---|
| TEST-001 | Test de `CFIdentitySet` sans collision de hash | aucun (consigne) | XS |
| MIN-001 | Valeurs par défaut `focusableAdded`/`rejectedRoles` inutilisées | aucun (consigne) | XS |

Fichiers modifiés :
- `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/020-cef-web-hints/Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`
- `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/020-cef-web-hints/Sources/RoadieDaemon/AppTargetQueryService.swift`

Tests : `./scripts/test` 836 tests, 90 suites, exit 0 avant ; exit 0 après les deux corrections. Simulation jetable (hors projet, supprimée) : l'ancien `Set<CFHashCode>` échoue sur les nouvelles entrées du test.

### Non traités
| Finding | Raison |
|---|---|
| QUAL-001 | MEDIUM, extraction de fonctions = choix de structure |
