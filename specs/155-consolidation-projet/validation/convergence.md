# Convergence — 10 novembre 2026

CONVERGED pour le code, un passage ; aucune tâche ajoutée. tasks.md est resté inchangé pendant le contrôle.
51 tâches de développement vérifiées. T052/T053 portent audit/revue et opérations de livraison.
FR-027 : les preuves Git, publication, installation et runtime ne sont pas anticipées ; elles restent à produire en T053.

| Exigence | Réalisation | Vérification |
|---|---|---|
| FR-001 | README.fr.md:290 | specs/155-consolidation-projet/validation.md:10 |
| FR-002 | docs/decisions/030-native-command-input.md:1 | specs/155-consolidation-projet/tasks.md:69 |
| FR-003 | .gitignore:21 | specs/155-consolidation-projet/tasks.md:75 |
| FR-004 | scripts/package-dmg:8 | Tests/RoadieDaemonTests/CLICommandRouterTests.swift:95 |
| FR-005 | scripts/install:102 | scripts/tests/test_lifecycle.py:326 |
| FR-006 | Sources/roadied/main.swift:652 | Tests/RoadieDaemonTests/Spec155BuildIdentityTests.swift:30 |
| FR-007 | Sources/RoadieDaemon/DaemonHealth.swift:384 | Tests/RoadieDaemonTests/Spec155BuildIdentityTests.swift:35 |
| FR-008 | Sources/RoadieDaemon/CLICommandRouter.swift:871 | Tests/RoadieDaemonTests/CLICommandRouterTests.swift:95 |
| FR-009 | Sources/RoadieCore/Config.swift:1738 | Tests/RoadieDaemonTests/Spec155ConfigGuardTests.swift:29 |
| FR-010 | Sources/RoadieCore/Config.swift:105 | Tests/RoadieDaemonTests/Spec155ConfigGuardTests.swift:41 |
| FR-011 | docs/dev/ajouter-un-reglage.md:1 | specs/155-consolidation-projet/tasks.md:118 |
| FR-012 | AGENTS.md:5 | specs/155-consolidation-projet/tools/deplacer_journal.py:75 |
| FR-013 | AGENTS.md:20 | specs/155-consolidation-projet/validation.md:14 |
| FR-014 | Sources/RoadieDaemon/AppTargetQueryService.swift:1013 | specs/155-consolidation-projet/validation.md:15 |
| FR-015 | Sources/RoadieDaemon/DropPreviewController.swift:635 | specs/155-consolidation-projet/validation.md:16 |
| FR-016 | Sources/RoadieDaemon/ShellCompletion.swift:8 | Tests/RoadieDaemonTests/Spec155ShellCompletionTests.swift:10 |
| FR-017 | scripts/coverage:23 | specs/155-consolidation-projet/validation.md:18 |
| FR-018 | .github/workflows/tests.yml:6 | specs/155-consolidation-projet/validation.md:23 |
| FR-019 | Sources/RoadieDaemon/ReplayableSnapshotProvider.swift:11 | specs/155-consolidation-projet/tools/extraire_fournisseur.py:61 |
| FR-020 | Sources/RoadieDaemon/ReleaseCheck.swift:91 | Tests/RoadieDaemonTests/Spec155ReleaseCheckTests.swift:70 |
| FR-021 | Sources/RoadieDaemon/CLICommandRouter.swift:875 | Tests/RoadieDaemonTests/Spec155ReleaseCheckTests.swift:44 |
| FR-022 | specs/155-consolidation-projet/validation/inventaire-publications.md:1 | specs/155-consolidation-projet/validation/retrait-publications.md:3 |
| FR-023 | CHANGELOG.md:8 | docs/en/cli.md:36 |
| FR-024 | specs/155-consolidation-projet/decisions.md:112 | specs/155-consolidation-projet/validation.md:23 |
| FR-025 | LICENSE:2 | README.md:869 |
| FR-026 | Sources/RoadieCore/Config.swift:103 | Tests/RoadieDaemonTests/Spec155LauncherTests.swift:108 |
| FR-027 | scripts/package-dmg:11 | specs/155-consolidation-projet/tasks.md:393 |
| FR-028 | README.fr.md:408 | scripts/install:27 |
| FR-029 | specs/155-consolidation-projet/validation/retrait-publications.md:3 | specs/155-consolidation-projet/validation/retrait-publications.md:7 |
| FR-030 | scripts/tests/test_lifecycle.py:326 | Tests/RoadieDaemonTests/Spec155ConfigGuardTests.swift:45 |

## Second passage après correction du gabarit CI

CONVERGED. Aucune tâche ajoutée et aucune case décochée. Seule la référence checkout
du gabarit et de sa recette a changé ; elle est identique au workflow réel déjà épinglé.
Aucun changement de code Swift ou de test depuis la suite complète réussie.
