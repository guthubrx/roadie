# Journal d'Implémentation — SPEC-011 Composants atomiques

## Métadonnées

- **Spec** : `011-atomic-components`
- **Branche** : `main` (refactor localisé, pas de worktree dédié)
- **Démarré** : 2026-05-10
- **Terminé** : 2026-05-10
- **Statut** : Implemented

## Tests finaux

- **Suite complète** : 420/420 OK en 0,283 s (PATH Xcode requis)
- **Tests SPEC-011 dédiés** : 11/11 OK en 0,006 s
  - `ComponentLockFileTests` : 4 cas
  - `QueryComponentsTests` : 2 cas
  - `ComponentSubcommandTests` : 3 cas (invariants noms canoniques)
  - `RoadiedRunFlagsTests` : 2 cas (invariants flags `--no-*`)

## Fichiers créés

- `Sources/RoadieDaemon/ComponentLockFile.swift` (struct publique + enum d'erreur)
- `Tests/RoadieDaemonTests/ComponentLockFileTests.swift`
- `Tests/RoadieDaemonTests/QueryComponentsTests.swift`
- `Tests/RoadieDaemonTests/ComponentSubcommandTests.swift`
- `Tests/RoadieDaemonTests/RoadiedRunFlagsTests.swift`
- `Scripts/start-modular`
- `specs/011-atomic-components/{spec,plan,tasks,research,quickstart}.md`
- `specs/011-atomic-components/contracts/component-lock.md`
- `specs/011-atomic-components/implementation.md`

## Fichiers modifiés

- `Sources/roadied/main.swift` :
  - `printUsage()` étendu (nouveaux flags + sous-commandes)
  - Ajout helper `runComponent(_:start:)` avec `DispatchSourceSignal` SIGTERM/SIGINT/SIGHUP
  - Mode `run` : flags symétriques `--no-tiler`, `--no-border`, `--no-focus-mouse`, `--no-titlebar-menu`, `--no-target-mode` ; bloc Timer/AXWindowEventObserver conditionné sur `shouldStartTiler`
  - Sous-commandes : `tiler`, `rail`, `border`, `focus-mouse`, `titlebar-menu`, `target-mode`, `restore-safety`
- `Sources/RoadieDaemon/AutomationQueryService.swift` : case `"components"` dans `query(_:)`
- `Sources/roadie/main.swift` : usage `query ... |components`

## Couverture EF / SC

| Critère | Vérifié par |
|---|---|
| EF-001 (rétro-compat `roadied run --yes`) | T024 (lecture code : aucun composant supprimé du flux par défaut) |
| EF-002 (flags `--no-*`) | T016-T018 + `RoadiedRunFlagsTests` |
| EF-003 (sous-commandes) | T006-T014 + `ComponentSubcommandTests` |
| EF-004 (autonomie sous-commandes) | `runComponent(_:start:)` instancie un seul contrôleur |
| EF-005 (lock PID) | `ComponentLockFileTests` (4 cas) |
| EF-006 (état partagé fichiers) | Hérité SPEC-002 (NSLock EventLog) |
| EF-007 (`roadie query components`) | `QueryComponentsTests` (2 cas) |
| EF-008 (flag inconnu → erreur) | Parser existant `default: printUsage(); exit(64)` |
| EF-009 (`Scripts/start` non modifié) | `git status Scripts/start` propre |
| SC-001 (RAM rail seul < 50% du run complet) | Mesure manuelle dans quickstart |
| SC-002 (démarrage < 5s) | Mesure manuelle dans quickstart |
| SC-003 (kill propre sans cascade) | Smoke test manuel (les composants n'observent pas les autres PID) |
| SC-004 (rétro-compat même composants) | Code par défaut active tout, lecture diff |
| SC-005 (252 tests passants) | Dépassé : 420/420 OK |

## Notes techniques

- `DispatchSourceSignal` choisi à la place de `signal(3)` standard car les closures Swift ne sont pas `@convention(c)`. Le pattern est aussi utilisé par Swift Argument Parser.
- Lock PID : isolation per-process en mode test (`NSTemporaryDirectory/roadie-test-locks-<pid>/`) pour ne pas perturber un daemon réel pendant `swift test`.
- Le bloc tiler dans `case "run"` reste structurellement séparé du bloc UI : si l'utilisateur passe `--no-tiler`, le `LayoutMaintainer` n'est instancié que pour préserver les références mais le timer/observer ne démarrent pas.
- Aucune modification de `Scripts/start` / `Scripts/stop` : ces scripts continuent à fonctionner sur le mode legacy.
- Le verrou inter-process JSONL reste **non-implémenté** (acceptation du risque documenté dans `research.md`). Write atomique POSIX < 4 KB est suffisant en pratique. À revisiter en cycle 2 si corruption observée.

## Prochaines actions recommandées

1. Lancer `/audit 011` pour vérifier la conformité (Article XVIII, complexité algorithmique).
2. Tester manuellement le mode modulaire : `./Scripts/start-modular` puis `roadie query components`.
3. Mesurer SC-001 (RAM) et SC-002 (startup) sur la machine de l'utilisateur, consigner dans `quickstart.md`.
4. Si retours positifs, ajouter des plists launchd par composant en SPEC-012 (extension naturelle).
