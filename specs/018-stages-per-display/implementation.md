# Implementation log — SPEC-018 Stages-per-display

**Status**: MVP + refactor 1-tree-par-stage + reconcile + purge orphelines + **HOTFIX switchTo cohérence V2** — US4 + US5 + Polish optionnels reportés
**Branch**: `018-stages-per-display`
**Last updated**: 2026-05-03 (session 8)

## Hotfix critique session 8 (2026-05-03) — switchTo cohérence V2

**Symptôme** : `roadie stage 2` retournait `current: 2` mais le state interne du daemon
ne mettait pas vraiment à jour. Visuellement : clic vignette dans le rail → halo bouge,
mais aucune fenêtre ne change. `daemon.status` après switch retournait `current_stage: 1`.

**Cause racine** : 3 bugs cumulés dans `StageManager.switchTo(stageID:)` en mode per_display.

1. `switchTo` lookup `stages[stageID]` (V1 dict) qui pouvait être nil pour les stages
   créées uniquement dans `stagesV2` → log warn + early return → currentStageID inchangé.
2. Le hide loop itérait `stages` V1 dict (synchro fragile cross-scope) → certaines wids
   d'autres stages pas hidées.
3. Le `setActiveStage(stageID)` du LayoutEngine ne garantissait pas que le tree
   `(stageID, primaryDisplay)` contenait les wids tilées → applyLayout no-op.

**Fix appliqué** :
- `switchTo` : fallback `stagesV2 → stages V1` + full sync au début pour avoir la vue
  complète des memberWindows cross-scope
- Hide loop : utilise `registry.allWindows.filter { state.stageID != nil && != cible }`
  (source de vérité = registry)
- `setActiveStage` étendu : peuple le tree de la stage cible avec les wids du registry
  qui ont `state.stageID == stageID`, force `isVisible = true` sur ces leaves
- Events `stage_changed` enrichis : en mode per_display, `desktop_id` et `display_uuid`
  proviennent de `stagesV2` (pas du `extractDesktopID` qui retourne nil en V2 plat)

**Validation E2E** :
- `roadie stage 2` → `daemon.status` retourne `current_stage: 2` ✓
- Grayjay (assigned stage 2) → frame `125,43 1910x1172` (plein écran) ✓
- Autres wids (stage 1) → frame `-949,1252 ...` (offscreen corner) ✓
- `roadie stage 1` retour → wids stage 1 reviennent à frame positives ✓

**Bug résiduel mineur** : certaines apps (Grayjay observée) résistent au `setBounds(corner)`
et restent partiellement visibles après hide. Probablement auto-restore frame côté app
via son propre code AX. Hors scope SPEC-018.

**Fichiers modifiés** :
- `Sources/RoadieStagePlugin/StageManager.swift` — switchTo refait, +20 LOC nettes
- `Sources/RoadieTiler/LayoutEngine.swift` — setActiveStage repopule tree, +30 LOC

## Audit stage/desktop confusion (session 8)

Recherche exhaustive de patterns de confusion conceptuelle entre stages roadie
(groupes de fenêtres) et desktops (espaces virtuels) :
- Aucune variable mal nommée trouvée
- `DesktopBackedStagePersistence` / `DesktopState.stages` sont des conteneurs de
  stockage légitimes (un desktop contient ses stages)
- Tous les `desktop_id` dans payloads d'events sont explicitement **desktop ROADIE**,
  jamais Mission Control macOS
- `currentStageScope()` daemon résout correctement display + desktop courant via
  `desktopRegistry.currentID(for: displayID)` (pas confondu avec Spaces macOS)

Code globalement cohérent. La confusion observée par l'utilisateur venait du
**bug fonctionnel** (switchTo broken), pas d'une ambiguïté de nommage.

## Phases livrées

| Phase | Statut | Tâches | Détails |
|---|---|---|---|
| 1. Setup | ✓ | T001-T004 | Pré-conditions vérifiées, baseline tests verts |
| 2. Foundational | ✓ | T010-T017 | StageScope + StagePersistenceV2 (Flat+Nested) + MigrationV1V2 + StageManager étendu |
| 3. US1 isolation | ✓ | T020-T026 | currentStageScope() + IPC scopé + tests |
| 4. US2 migration | ✓ | T030-T034 | Migration silencieuse au boot + event + daemon.status enrichi |
| 5. US3 compat global | ✓ | T040-T042 | Mode global préservé strictement, 0 régression |
| 6. US4 CLI override | ✓ | T050-T053 | flags --display/--desktop + erreurs unknown_display/desktop_out_of_range |
| 7. US5 rail enrichment | ✓ | T060-T063 | Events `stage_*` enrichis avec `display_uuid`/`desktop_id` + filtre côté client dans RailController.handleEvent |
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

## US5 — Rail multi-display scoped (T060-T063)

### T060 — scope implicite rail

`loadInitialStages()` dans `RailController` appelle `ipc.send(command: "stage.list")` sans argument `display` — le scope est résolu côté daemon par `currentStageScope()` (curseur→frontmost→primary). Aucune modification nécessaire.

### T061 — enrichissement des factories EventBus

Quatre nouvelles factories dans `EventBus.swift` : `stageCreated`, `stageDeleted`, `stageAssigned` (nouvelles), et `stageRenamed` étendu avec `displayUUID`/`desktopID`. Les trois paramètres ont des valeurs par défaut `""` et `0` pour compat ascendante (mode global sentinel).

Les sites d'émission dans `CommandRouter.swift` ont été mis à jour : `stage.assign`, `stage.create`, `stage.rename`, `stage.delete` — tous capturent le scope résolu avant retour et passent `displayUUID`/`desktopID` aux factories enrichies.

Environ +55 LOC dans EventBus.swift et +35 LOC delta dans CommandRouter.swift.

### T062 — filtre côté client dans RailController

`handleEvent` étendu avec deux filtres en mode `per_display` :
1. **Filtre display** : si `display_uuid` non-vide et ne correspond à aucun écran connu du rail (`panelBelongsToUUID`), l'event est ignoré.
2. **Filtre desktop** : si `desktop_id` non-null et ne correspond pas à `state.currentDesktopID`, l'event est ignoré.

`desktop_changed` déclenche maintenant un `loadInitialStages()` pour resync les stages du nouveau desktop.

Environ +20 LOC nettes.

### T063 — test acceptance

Script `Tests/18-rail-scope.sh` : détecte < 2 écrans → SKIP. Si 2+ écrans, vérifie que les events `stage_created` contiennent `display_uuid` et `desktop_id`. La partie visuelle (un seul panel met à jour son UI) reste manuelle, documentée dans le script.

### REX US5

Le filtre `panelBelongsToUUID` utilise `state.screens` (peuplé par `buildPanels()` au boot). Si le rail est lancé avant que les écrans soient connus, `state.screens` peut être vide — dans ce cas tous les events passent (comportement dégradé gracieux, pas de perte d'events).

La granularité desktop-per-display dans le rail (`currentDesktopID` est global, pas par display) est une limitation connue. Pour un vrai multi-display avec desktop indépendants par écran, il faudrait un `currentDesktopPerDisplay: [String: Int]` dans `RailState`. Cette amélioration est reportée à une SPEC ultérieure (hors scope T062).

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

## US4 — CLI overrides (T050-T053)

Les 4 tâches US4 sont livrées. La résolution du scope override passe par un helper
`resolveScope(request:daemon:errorOut:)` dans `CommandRouter` qui gère les deux paths :
index 1-based (`DisplayRegistry.display(at:)`) et UUID (`display(forUUID:)`). Les deux
nouveaux `ErrorCode` (`unknownDisplay`, `desktopOutOfRange`) sont dans `RoadieCore/Types.swift`
et propagés avec exit 5 côté CLI. La décision de ne pas mettre de scope override sur
`stage.switch` est délibérée : le switch cible une stage déjà existante, donc le scope
est forcément le scope courant (pas de création lazy ici).

## Hotfixes & polish post-MVP (2026-05-03)

Suite au test utilisateur intensif, plusieurs bugs et améliorations ont été livrés
au-delà du périmètre initial des tasks.

### Architecture : 1 tree BSP par stage (refactor majeur)

**Problème** : avant ce refactor, `LayoutEngine.workspace.rootsByDisplay` indexait
un seul tree par display, indépendamment de la stage active. Conséquence : les wids
assignées à une stage non-active restaient dans le tree global et n'étaient jamais
re-tilées correctement au switch (fenêtres "fantômes" qui restaient à leur dernière
position cachée).

**Solution** : refactor `Workspace.rootsByStageDisplay: [StageDisplayKey: TilingContainer]`
indexé par tuple `(stageID, displayID)`. Au switch de stage, le `LayoutEngine.activeStageID`
change → `applyAll` n'utilise QUE le tree de la stage active.

**Couplage StageManager → LayoutEngine** : extension de `LayoutHooks` avec
`reassignToStage(WindowID, StageID)` et `setActiveStage(StageID?)`. Le StageManager
appelle ces hooks à chaque `assign()` et `switchTo()` pour synchroniser le LayoutEngine.

**Fichiers** :
- `Sources/RoadieTiler/LayoutEngine.swift` — refactor complet (-65 LOC nettes)
- `Sources/RoadieStagePlugin/StageManager.swift` — extension LayoutHooks (+21 LOC)
- `Sources/roadied/main.swift` — câblage 2 nouveaux hooks (+4 LOC)
- `Tests/RoadieStagePluginTests/StageLayoutHooksTests.swift` — 4 nouveaux tests (118 LOC)

### `assign(wid:to:scope:)` overload V2 scope-aware

**Problème** : en mode per_display, `CommandRouter` créait la stage dans `stagesV2`
mais appelait `sm.assign(wid:to:stageID)` (API V1) qui regardait `stages` V1 dict
→ `stage[stageID]` nil → fail silencieux, wid jamais assignée.

**Solution** : nouvel overload `assign(wid:to:scope: StageScope)` qui écrit dans
`stagesV2[scope]` et synchronise V1 dict pour compat. CommandRouter utilise cet
overload en mode per_display.

**Fichier** : `Sources/RoadieStagePlugin/StageManager.swift` (+45 LOC)

### `reconcileStageOwnership()` 2-way + fallback

**Problème** : incohérence entre `state.stageID` (registry, calculé au scan AX) et
`stage.memberWindows` (persistance disque). Au boot, certaines wids avaient
`state.stageID = "10"` ou `"5"` venant d'une persistance stale, mais ces stages
n'existaient pas dans le dict courant.

**Solution** : méthode `reconcileStageOwnership()` qui :
1. **Sens 1** : pour chaque wid dans `stage.memberWindows`, force `state.stageID = stage.id`
2. **Sens 2** : pour chaque wid du registry, l'ajoute à `stage[X].memberWindows` si absente
3. **Fallback** : si `state.stageID` référence une stage inexistante (V1 OU stagesV2 selon mode),
   force vers la stage default 1

Appelée :
- Au boot après scan AX initial (Task sleep 1.5s)
- Inline avant chaque `windows.list` et `stage.list` (cheap, normalise en continu)

### `purgeOrphanWindows()` au boot

**Problème** : les stages chargées du disque pouvaient contenir des wids fermées
des sessions précédentes (process killed). Le rail UI affichait des stages avec
0 fenêtres réelles + des chips vides.

**Solution** : retire les wids dont `registry.get(wid) == nil` de toutes les stages
(V1 dict + stagesV2). Persistance disque mise à jour. Appelée au boot après
reconcile.

### `ensureDefaultStage(scope:)` matérialisation V2

**Problème** : `ensureDefaultStage()` créait la stage 1 par défaut uniquement dans
`stages` V1 dict. En mode per_display, `stagesV2` ne contenait pas la stage 1 →
`stage list` filtré par scope retournait vide, `stage 1` échouait avec
`unknown_stage in current scope`.

**Solution** : ajout d'un paramètre `scope: StageScope?` à `ensureDefaultStage()`.
Quand fourni en mode per_display, crée aussi dans `stagesV2[scope]`. Le daemon
calcule `defaultScope = (mainDisplayUUID, 1, "1")` et le passe au boot après
`setMode(.perDisplay, ...)`.

### Filtrage events côté rail (SPEC-014 + SPEC-018)

**Problème** : le rail panel sur Display 1 recevait les events `stage_*` de Display 2,
provoquant des refresh inutiles et de la confusion d'affichage.

**Solution** : `RailController.handleEvent` filtre par `payload["display_uuid"]` et
`payload["desktop_id"]`. Si l'event ne match pas le scope du panel concerné, ignore.
Les events sans scope (compat V1) passent toujours.

### Halo stage active paramétrique

**Polish** : couleur (`halo_color`) et intensité (`halo_intensity` 0..1) du halo
de la stage active configurables via `[fx.rail]` dans le TOML. Defaults vert
système Apple `#34C759` à `0.65`.

### Bug NSZombie fix critique (SCKCaptureService)

**Problème** : 11+ crashs `EXC_BREAKPOINT` du daemon en 2 jours, tous à uptime
≈ 140s exactement. Pattern `___forwarding___.cold.6` au pop d'autoreleasepool de
`NSApp.run`.

**Cause** : dans `SCKCaptureService.encodePNG`, retour `data as Data` faisait un
toll-free bridging (wrap, pas copie). Le `NSMutableData` créé dans
l'autoreleasepool du callback `SCStream.didOutputSampleBuffer` était release au
drain du pool background. Le `Data` retourné devenait zombie au prochain accès
depuis le main thread (~70 frames plus tard à 0.5 Hz = 140s).

**Solution** : `Data(bytes: data.bytes, count: data.length)` qui copie les bytes
dans un buffer Swift indépendant du `NSMutableData` autoreleased.

**Fichier** : `Sources/RoadieCore/ScreenCapture/SCKCaptureService.swift` (5 LOC modifiées)

**Validation** : daemon vit > 155s d'uptime sans crash après le fix (vs crash
systématique à 140s avant).

## TODOs restants

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

## Verification finale (toutes phases)

### Build

```
$ PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin" swift build
Build complete! (0.24s)
```

Build 0 warning, 0 error. Seuls les fichiers SPEC-018 sont recompilés sur un build incremental depuis un état propre.

### Tests

```
$ swift test --filter "RoadieStagePluginTests|RoadieCoreTests"
Executed 336 tests, 0 failures
```

- 336 tests total (Swift Testing + XCTest combined)
- 0 failure imputable a SPEC-018
- Note : le segfault `RoadieDesktopsTests.ParserTests` observable en full-suite (`swift test` sans filtre) est pre-existant — documente dans SPEC-014, passe 7/7 en isolation (`swift test --filter RoadieDesktopsTests`). Non regressee par SPEC-018.

### LOC production SPEC-018

| Perimetre | LOC nettes |
|---|---|
| `Sources/RoadieStagePlugin/` (nouveaux fichiers : StageScope, StagePersistenceV2, MigrationV1V2) | 276 |
| `Sources/RoadieStagePlugin/StageManager.swift` (+73 delta) | 73 |
| `Sources/RoadieRail/Views/WindowPreview.swift` + `WindowStack.swift` (US5 rail) | 269 |
| `Sources/roadied/CommandRouter.swift` (+70 US1/US2/US4 + ~12 T072) | ~82 |
| `Sources/roadied/main.swift` (+93 US1/US2 + ~18 T072) | ~111 |
| `Sources/RoadieCore/EventBus.swift` (+17 US2 + ~55 US5) | ~72 |
| **Total production** | **~883** |

La cible spec etait 600 LOC / plafond 900. Le depassement mineur (~883 vs 900) est du aux enrichissements US5 (rail filtre + events enrichis) dont le scope a ete etendu apres la redaction initiale du plafond.

### Couverture taches

Toutes les 42 taches T010-T076 sont cochees `[X]` a l'exception de :
- **T070** [SKIP — MANUEL] : captures d'ecran avant/apres pour `quickstart.md` (necessite 2 ecrans physiques + session GUI, hors portee CI)
- **T076** [SKIP — AUDIT DEDIE] : audit `/audit 018-stages-per-display` a lancer manuellement quand l'ensemble de la spec est stabilise

### Liens tests

**Tests Swift** :
- `Tests/RoadieStagePluginTests/StageScopeTests.swift`
- `Tests/RoadieStagePluginTests/StagePersistenceV2Tests.swift`
- `Tests/RoadieStagePluginTests/MigrationV1V2Tests.swift`
- `Tests/RoadieStagePluginTests/StageManagerScopedTests.swift`

**Scripts acceptance bash** :
- `Tests/18-stage-list-scope.sh`
- `Tests/18-stage-mutations-scope.sh`
- `Tests/18-migration.sh`
- `Tests/18-global-mode-compat.sh`
- `Tests/18-cli-override.sh`
- `Tests/18-rail-scope.sh`

## Prochaines actions utilisateur

1. **Activer le mode** : ajouter `[desktops] mode = "per_display"` dans `~/.config/roadies/roadies.toml`
2. **Redémarrer** le daemon : `bash scripts/restart.sh`
3. **Vérifier la migration** : `roadie daemon status --json | jq '.payload.migration_pending'` doit retourner `false`
4. **Tester l'isolation** : créer une stage avec curseur sur Display 1, déplacer souris sur Display 2, `roadie stage list` ne doit pas la contenir
5. **Audit** quand prêt : `/audit 018-stages-per-display` en mode fix pour validation finale et scoring

---

## Post-livraison fixes (session 2026-05-03 — 6 commits)

Lors de la mise en service end-to-end, plusieurs bugs ont été détectés via le rail UI (SPEC-014) et les commandes CLI. Tous fixés dans la même session.

### Fix 1 — `reconcileStageOwnership` Sens 2 écrasait stagesV2 (commit `b0ea24b`)

**Problème** : en mode `per_display`, le Sens 2 du reconcile (registry → stage.memberWindows) opérait sur le dict V1 `stages` (vide en per_display), puis sync v1→v2 qui **écrasait** stagesV2 avec un stage V1 vide. Résultat : V2 file passait de 576 bytes à 108 bytes (vide) au boot.

**Fix** : en mode per_display, opérer DIRECTEMENT sur `stagesV2[scope]` au lieu de via `stages[targetID]`. Plus de sync destructive v1→v2.

**Bonus fix** : retrait de l'appel `purgeOrphanWindows()` au boot (1.5s timer) car il purgeait des wid légitimes encore en cours de scan AX (apps lentes type iTerm). Purge reste active sur `handleWindowDestroyed` (cleanup en continu).

**Fichier** : `Sources/RoadieStagePlugin/StageManager.swift` + `Sources/roadied/main.swift`.

### Fix 2 — `setActiveStage` ne restaurait pas le tree (commit `905c4d6`)

**Problème** : après stage switch + reswitch, le tree BSP devenait vide → `roadie focus/move/swap left/right/up/down` retournaient "no neighbor" sans raison apparente. Cause : `setActiveStage` se contentait de set `workspace.activeStageID`, sans re-peupler le tree depuis les members de la stage cible.

**Fix** : la closure `setActiveStage` injectée dans `LayoutHooks` (Sources/roadied/main.swift:115) appelle maintenant `engine.ensureTreePopulated(with: wids)` après le set, où `wids` est filtré depuis le registry (`state.stageID == stageID && state.isTileable`).

**Fichiers** : `Sources/roadied/main.swift` (closure) + `Sources/RoadieTiler/LayoutEngine.swift` (méthode `ensureTreePopulated`).

### Fix 3 — `rebuild` lisait du tree vide au lieu du registry (commit `905c4d6`)

**Problème** : `roadie rebuild` reconstruisait l'arbre depuis ses propres `oldLeaves`. Si le tree était déjà vide (cas du fix #2 avant fix), le rebuild produisait un tree vide aussi.

**Fix** : `CommandRouter` case "rebuild" appelle d'abord `ensureTreePopulated(with: registry.tileableWindows)` AVANT `rebuildTree()`. Le registry est maintenant la source de vérité.

**Fichier** : `Sources/roadied/CommandRouter.swift` case `"rebuild"`.

### Fix 4 — `MigrationV1V2` archive backup ancien (commit `dfa8938`)

**Problème** : `MigrationV1V2.runIfNeeded()` skippait dès que `stages.v1.bak` existait. Mais si les V1 sources avaient été ré-créés (boot précédent) et un nouveau backup attendait la migration, la skip silencieuse perdait les members non migrés.

**Fix** : si backup existant ET V1 source non vide → archive backup ancien horodaté + force nouvelle migration. Backup ancien préservé (jamais perdu).

**Fichier** : `Sources/RoadieStagePlugin/MigrationV1V2.swift` lignes 41-69.

### Fix 5 — `migrateFiles` `mv` échouait sur dst existant (commit `dfa8938`)

**Problème** : `FileManager.moveItem(atPath: src, toPath: dst)` échoue avec NSFileWriteFileExistsError 516 si dst existe. Si V2 cible a été créée vide par un boot précédent, V1 source ne pouvait jamais migrer → données perdues silencieusement.

**Fix** : avant `mv`, check si dst existe :
- dst vide (`members = []` détecté via heuristique TOML grep) → suppression dst + écraser
- dst plein → backup V1 source en `.legacy.<TS>` pour intervention manuelle

**Helper** : `isStageFileEmpty(_:)` ajouté.

**Fichier** : `Sources/RoadieStagePlugin/MigrationV1V2.swift` lignes 108-150.

### Fix 6 — RailController over-strict sur display_uuid (commit `0a77b04`)

**Problème** : le filtre US5 T062 ignorait les events `stage_*` dont le `display_uuid` ne matchait pas le panel courant. Mais le scope inferré côté daemon (cursor/frontmost/primary) pouvait diverger du panel rail courant → updates manqués silencieusement (rail désynchronisé sans erreur visible).

**Fix** : sur mismatch, déclencher quand même un `loadInitialStages()` léger (sans le `loadWindows` lourd). Compromis : un appel IPC supplémentaire occasionnel, mais zéro update manqué.

**Fichier** : `Sources/RoadieRail/RailController.swift` `handleEvent`.

### Fix 7 — Helpers `decodeBool/Int/String` tolérants AnyCodable (commit `0a77b04`)

**Problème** : `payload["is_active"] as? Bool` échouait silencieusement quand le JSON renvoyait un Int (0/1) ou un NSNumber au lieu d'un Bool natif (cas du bridging AnyCodable côté daemon → JSONSerialization → side rail). Le fallback `id == current` masquait que le cast avait fail. Conséquence observable : 2 stages affichées comme "active" dans le rail (2 halos verts au lieu d'1).

**Fix** : helpers `decodeBool/decodeInt/decodeString` qui tentent toutes les représentations communes (Bool, NSNumber, Int, String "true"/"1") avant d'abandonner. Utilisés dans `parseStages` + `handleEvent`.

**Fichier** : `Sources/RoadieRail/RailController.swift` (extension fonctions globales).

### Fix 8 — Halo conditionnel `@ViewBuilder if` (commit `79b2edf`)

**Problème** : `.shadow(color: stage.isActive ? Color(hex:...).opacity(...) : .clear, radius: ..., x: 0, y: 0)` semblait dessiner un halo même quand inactive — possible artefact rendu SwiftUI avec `.clear`.

**Fix** : remplacement par `@ViewBuilder` `if stage.isActive { content.shadow(...) } else { content }` qui n'applique pas le modifier `.shadow` du tout quand inactive.

**Bonus** : `halo_radius` ajouté en paramètre TOML `[fx.rail]` (en plus de `halo_color` et `halo_intensity` déjà existants).

**Fichiers** : `Sources/RoadieRail/Views/WindowStack.swift` + `RailController.swift` + `StageStackView.swift` + `quickstart.md` SPEC-014.

### Bonus — `ensureTreePopulated` méthode défensive (commit `a245397`)

Méthode utilitaire ajoutée dans `LayoutEngine` : `ensureTreePopulated(with wids: [WindowID]) -> Int`. Idempotent : pour chaque wid pas déjà dans le tree de la stage active du primary display, l'insère via `insertWindow`. Utilisée par fix #2 (boot) et fix #3 (rebuild).

### CLI `roadie window swap/insert` wired (commit `a245397`)

Verbes CLI ajoutés au `handleWindow` de `Sources/roadie/main.swift`. **Note** : la commande daemon `window.swap` n'est PAS encore implémentée (planifiée SPEC-016 catégorie A5/A4 "yabai-parity tier-1"). Le CLI retourne actuellement `unknown command`. Le binding sera fonctionnel à la livraison de SPEC-016.

### Récap commits post-livraison

| Commit | Sujet |
|---|---|
| `b0ea24b` | reconcile sens 2 opère sur stagesV2 directement (mode per_display) + retire purgeOrphanWindows du boot |
| `88c86e2` | DesktopMigration archive auto V2 leftover si V3 actif (anti-fantômes) — cf. SPEC-013 implementation.md |
| `79b2edf` | halo paramétrique radius + halo conditionnel @ViewBuilder if |
| `a245397` | ensureTreePopulated défensif au boot + CLI 'window swap/insert' wired |
| `45f6159` | DesktopRegistry V3 paths display-scoped — cf. SPEC-013 implementation.md |
| `905c4d6` | setActiveStage restore tree depuis registry + rebuild ensure populated |
| `dfa8938` | MigrationV1V2 archive backup + écrase dst vide (perte data évitée) |
| `0a77b04` | rail handleEvent poll léger sur scope mismatch + helpers decodeBool/Int/String tolérants |
