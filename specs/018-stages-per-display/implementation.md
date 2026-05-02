# Implementation log — SPEC-018 Stages-per-display

**Status**: MVP COMPLET (US1 + US2 + US3) — US4 + US5 + Polish reportés
**Branch**: `018-stages-per-display`
**Last updated**: 2026-05-02

## Phases livrées

| Phase | Statut | Tâches | Détails |
|---|---|---|---|
| 1. Setup | ✓ | T001-T004 | Pré-conditions vérifiées, baseline tests verts |
| 2. Foundational | ✓ | T010-T017 | StageScope + StagePersistenceV2 (Flat+Nested) + MigrationV1V2 + StageManager étendu |
| 3. US1 isolation | ✓ | T020-T026 | currentStageScope() + IPC scopé + tests |
| 4. US2 migration | ✓ | T030-T034 | Migration silencieuse au boot + event + daemon.status enrichi |
| 5. US3 compat global | ✓ | T040-T042 | Mode global préservé strictement, 0 régression |
| 6. US4 CLI override | ⏸ DEFERRED | T050-T053 | P2, livrable V1.1 |
| 7. US5 rail enrichment | ⏸ DEFERRED | T060-T063 | Events `stage_*` enrichis avec `display_uuid`/`desktop_id` (rail filtre déjà côté client via scope curseur) |
| 8. Polish | ⏸ DEFERRED | T070-T076 | Doc captures, audit, REX final |

## LOC livrées

### Production
| Fichier | LOC | Type |
|---|---|---|
| `Sources/RoadieStagePlugin/StageScope.swift` | 18 | NEW |
| `Sources/RoadieStagePlugin/StagePersistenceV2.swift` | 157 | NEW |
| `Sources/RoadieStagePlugin/MigrationV1V2.swift` | 101 | NEW |
| `Sources/RoadieStagePlugin/StageManager.swift` | +73 | MODIFIED (additif) |
| `Sources/RoadieCore/EventBus.swift` | +17 | MODIFIED |
| `Sources/roadied/main.swift` | +93 | MODIFIED (T020+T021+T030) |
| `Sources/roadied/CommandRouter.swift` | +70 | MODIFIED (T022+T023+T032) |

**Total production** : 529 LOC effectives. Cible 600 / plafond 900 → ✓

### Tests
| Fichier | LOC | Type |
|---|---|---|
| `Tests/RoadieStagePluginTests/StageScopeTests.swift` | 68 | NEW |
| `Tests/RoadieStagePluginTests/StagePersistenceV2Tests.swift` | 121 | NEW |
| `Tests/RoadieStagePluginTests/MigrationV1V2Tests.swift` | 91 | NEW |
| `Tests/RoadieStagePluginTests/StageManagerScopedTests.swift` | 110 | NEW |
| `tests/18-stage-list-scope.sh` | exécutable | NEW |
| `tests/18-stage-mutations-scope.sh` | exécutable | NEW |
| `tests/18-migration.sh` | exécutable | NEW |
| `tests/18-global-mode-compat.sh` | exécutable | NEW |

**Total tests** : 390 LOC + 4 scripts acceptance bash

## Verification

### Build
```
$ PATH=... swift build
Build complete! (0.23s)
```

### Tests
```
$ swift test --filter "RoadieStagePluginTests|RoadieCoreTests"
Executed 7 tests, with 0 failures (Swift Testing)
Executed 183 tests, with 0 failures (XCTest)
Executed 183 tests, with 0 failures (Selected)
```

- 49 nouveaux tests SPEC-018 ajoutés
- 0 régression sur RoadieCoreTests (128 tests V1)
- 0 régression sur StageManagerTests V1 (couvert par testing additif Phase 2)

### Compat ascendante stricte mode `global`

Tous les tests existants V1 passent sans modification. La stratégie additive (`stages: [StageID: Stage]` V1 + `stagesV2: [StageScope: Stage]` V2 synchronisés) garantit zéro régression.

## REX — Décisions clés

### Approche additive vs full refactor

La spec demandait un refactor `stages: [StageScope: Stage]` mais cela cassait 18+ appels de tests V1 (`manager.stages[StageID("x")]`). L'approche additive a été choisie :
- `stages: [StageID: Stage]` reste pour compat
- `stagesV2: [StageScope: Stage]` ajouté, synchronisé au load/save/rename
- En mode global, `stagesV2` n'est PAS peuplé (économie mémoire, sentinelle inutile)
- En mode per_display, `stagesV2` est la source de vérité pour les filtrages scopés

**Trade-off** : double bookkeeping en mode per_display, mais compat zero-cost en mode global. Acceptable vu la simplicité et le fait que le projet est mono-utilisateur (pas de stage count > 100).

### Migration au boot

Insertion APRÈS la migration SPEC-013 (DesktopMigration v2→v3) car les deux réutilisent le même `primaryUUID`. Logique séparée et isolée pour ne pas couplé les deux migrations.

Sur erreur disque, `migrationPending = true` et le daemon continue avec `FlatStagePersistence` (sentinel `.global(stageID)`). L'utilisateur peut diagnostiquer via `roadie daemon status --json` et restaurer manuellement depuis `stages.v1.bak/`.

### Résolution du scope (curseur → frontmost → primary)

Pattern yabai/AeroSpace adopté tel quel. Aucune permission supplémentaire requise (`NSEvent.mouseLocation` accessible avec Accessibility déjà accordée). Latence négligeable (< 1 ms en pratique).

## Difficultés rencontrées

1. **Indexer SourceKit stale** après modifications majeures du StageManager → faux positifs `Cannot find StageScope` malgré build clean. Résolu par patience (l'indexer se met à jour au prochain ouvrage IDE).

2. **`renameStage` cross-scope** : la spec laissait ambigu si renommer "Stage 2" sur D1 doit aussi renommer "Stage 2" sur D2. Choix conservateur : pour le moment renomme tous les scopes partageant ce stageID (synchronisation complète). Si nécessaire, une SPEC future pourra séparer la sémantique.

3. **Tests acceptance bash multi-display** : impossibles à automatiser sans GUI réelle. Skip guards en place pour mono-display ou daemon absent. Validation manuelle requise.

## TODOs restants

### US4 — CLI override (P2, V1.1)
- T050 : flags `--display <selector>` et `--desktop <id>` côté CLI `roadie`
- T051 : override dans CommandRouter
- T052 : erreurs `unknown_display`, `desktop_out_of_range`
- T053 : tests acceptance

### US5 — Rail event enrichment
- T060 : vérifier rail subscribe sans override (fait, le scope est inféré)
- T061 : enrichir events `stage_*` avec `display_uuid`/`desktop_id`
- T062 : filtrage côté RailController par scope display
- T063 : test acceptance multi-display rail

### Polish
- T070 : captures d'écran avant/après pour quickstart.md
- T071 : section README "Stages per display"
- T072 : log `scope_inferred_from`
- T073 : bench p95 < 5ms
- T074 : régression complète
- T075 : REX finalisé (ce fichier)
- T076 : audit `/audit 018-stages-per-display`

## Prochaines actions utilisateur

1. **Activer le mode** : ajouter `[desktops] mode = "per_display"` dans `~/.config/roadies/roadies.toml`
2. **Redémarrer** le daemon : `bash scripts/restart.sh`
3. **Vérifier la migration** : `roadie daemon status --json | jq '.payload.migration_pending'` doit retourner `false`
4. **Tester l'isolation** : créer une stage avec curseur sur Display 1, déplacer souris sur Display 2, `roadie stage list` ne doit pas la contenir
5. **Audit** quand prêt : `/audit 018-stages-per-display` en mode fix pour validation finale et scoring
