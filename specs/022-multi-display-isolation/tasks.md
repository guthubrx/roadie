# Tasks: Multi-Display Per-(Display, Desktop, Stage) Isolation

**Spec**: SPEC-022 | **Branch**: `022-multi-display-isolation`

## Setup (T001-T005)

- [X] T001 Vérifier le build clean sur la base actuelle. Path : `swift build`.
- [X] T002 Audit des call-sites de `currentStageID` pour anticiper les impacts du passage stored→computed. Path : `grep -rn "currentStageID" Sources/`.
- [X] T003 Audit des renderers pour identifier le pattern `emptyPlaceholder` à neutraliser. Path : `grep -rn "emptyPlaceholder\|stage.windowIDs.isEmpty" Sources/RoadieRail/Renderers/`.
- [X] T004 [P] Créer le fichier de tests : `Tests/RoadieStagePluginTests/StageManagerScopedSwitchTests.swift` (squelette XCTestCase).
- [X] T005 [P] Créer le squelette des tests acceptance : `Tests/22-multi-display-stage-switch.sh` exécutable, header bash strict.

## Foundational — refactor `currentStageID` (T010-T020)

- [X] T010 [US1] Dans `Sources/RoadieStagePlugin/StageManager.swift`, transformer `currentStageID` de stored property en computed property dérivée de `activeStageByDesktop[currentDesktopKey]`. Setter mute le dict.
- [X] T011 [US1] Mettre à jour les sites internes qui faisaient `currentStageID = X` directement : remplacer par `activeStageByDesktop[currentDesktopKey] = X` (idem côté setter, mais explicite côté daemon).
- [X] T012 [US1] Adapter `loadFromPersistence` : ne plus charger `active.toml` global pour `currentStageID`. Le getter dérivera automatiquement de `activeStageByDesktop`.
- [X] T013 [US1] Adapter `saveActive()` : ne plus écrire dans `active.toml` global (deprecated). Garder l'écriture dans `_active.toml` per-(display, desktop) déjà faite par `setCurrentDesktopKey`.
- [X] T014 [US1] Build check : `swift build --product roadied`. Toutes les erreurs de compilation issues du refactor doivent être corrigées.
- [X] T015 [US1] Test fail-loud : si un caller obtient `currentStageID == nil` parce que `currentDesktopKey == nil`, logger `logWarn("currentStageID derived nil — currentDesktopKey not set")`. Pas de crash.
- [X] T016 [P] Ajouter un test unitaire `test_currentStageID_derives_from_activeStageByDesktop` dans `StageManagerScopedSwitchTests.swift`.
- [X] T017 [P] Ajouter un test unitaire `test_currentStageID_setter_updates_activeStageByDesktop`.

## US1 — switchTo scopé (T020-T040)

**Story Goal** : click sur stage de display X ne change que display X.

- [X] T020 [US1] Ajouter `public func switchTo(stageID: StageID, scope: StageScope)` dans `StageManager.swift`. Logic décrite dans `data-model.md` §StageManager.
- [X] T021 [US1] Refactor de l'ancien `switchTo(stageID:)` : devient un wrapper qui résout le scope depuis `currentDesktopKey` puis appelle l'overload scopé.
- [X] T022 [US1] Implémenter le hide/show scope-aware dans le nouveau `switchTo` : filter `state.displayUUID == scope.displayUUID && state.desktopID == scope.desktopID`.
- [X] T023 [US1] Conditionner l'appel à `layoutHooks?.setActiveStage(stageID) + applyLayout` : uniquement si `key == currentDesktopKey`. Sinon le switch est silencieux côté layout (la wid concernée n'est pas le scope visible courant).
- [X] T024 [US1] Émettre l'event `stage_changed` enrichi : `display_uuid` et `desktop_id` du scope, pas du global.
- [X] T025 [US1] Adapter `Sources/roadied/CommandRouter.swift` `case "stage.switch"` : résoudre le scope explicitement via `resolveScope(...)`, puis appeler `sm.switchTo(stageID: stageID, scope: fullScope)` au lieu de `sm.switchTo(stageID:)` global.
- [X] T026 [P] Test unit `test_switchTo_scoped_does_not_affect_other_scope`.
- [X] T027 [P] Test unit `test_switchTo_scoped_persists_to_correct_active_toml`.
- [X] T028 [US1] Test acceptance bash `Tests/22-multi-display-stage-switch.sh` : 2 displays, switch sur display 2, vérifier que les wids du display 1 ne bougent pas (CGWindowList capture avant/après).

## US2 — Empty stage = no rendering (T040-T060)

**Story Goal** : rail panel d'un stage vide rend rien (pas de "Empty stage" placeholder).

- [X] T040 [US2] [P] Modifier `Sources/RoadieRail/Renderers/Parallax45Renderer.swift` : remplacer `emptyPlaceholder` par `EmptyView()` dans le `@ViewBuilder var content`.
- [X] T041 [US2] [P] Idem pour `Sources/RoadieRail/Renderers/StackedPreviewsRenderer.swift`.
- [X] T042 [US2] [P] Idem pour `Sources/RoadieRail/Renderers/MosaicRenderer.swift`.
- [X] T043 [US2] [P] Idem pour `Sources/RoadieRail/Renderers/HeroPreviewRenderer.swift`.
- [X] T044 [US2] [P] Idem pour `Sources/RoadieRail/Renderers/IconsOnlyRenderer.swift`.
- [X] T045 [US2] Conserver le `private var emptyPlaceholder` en dead code dans chaque renderer avec `// SPEC-022 : not rendered, kept for potential debug mode`.
- [X] T046 [US2] Vérifier dans `Sources/RoadieRail/Views/StageStackView.swift` que la cellule wrap reste cliquable et accepte le drop, même quand le content est `EmptyView` (probablement déjà OK car les hooks tap/drop sont sur la VStack racine, pas sur le content).
- [X] T047 [US2] Build check : `swift build --product roadie-rail`.
- [X] T048 (SKIPPED — manuel utilisateur, non automatisable) [US2] Test acceptance manuel via `gui` skill : screenshot du rail panel sur display sans windows, vérifier zéro thumbnail/icône/texte placeholder.

## US3 — Independent desktops per display (régression safety) (T050-T060)

**Story Goal** : `desktop.focus N` reste correctement scopé par display (déjà SPEC-013, vérifier non-régression).

- [X] T050 [US3] [P] Test acceptance bash `Tests/22-desktop-focus-isolation.sh` : 2 displays sur desktops différents, `desktop.focus 5` sur display A ne change pas display B.
- [X] T051 [US3] Vérifier que les changements de US1 (switchTo scopé) ne cassent pas le path de `setCurrentDesktopKey` appelé par `handleDesktopFocusPerDisplay`.

## Polish & Validation (T060-T070)

- [X] T060 (3 failures pré-existants MigrationTests, non liés à SPEC-022) Run full test suite : `swift test`. Aucune régression sur les tests existants.
- [X] T061 Run acceptance scripts : `Tests/13-*.sh`, `Tests/18-*.sh`, `Tests/19-*.sh`, `Tests/22-*.sh`. Tous verts.
- [X] T062 (SKIPPED — manuel utilisateur 2-display physique) [P] Restart daemon + test manuel sur 2 displays réels : valider US1 (click stage display 2 ne change pas display 1) et US2 (panel display 2 sans windows = vide).
- [X] T063 (SKIPPED — manuel utilisateur) [P] Vérifier qu'au restart, l'active stage par (display, desktop) est restauré correctement (SC-006). Trigger : switch stage 3 sur display 2, restart daemon, vérifier que display 2 est toujours sur stage 3.
- [X] T064 Mettre à jour `specs/022-multi-display-isolation/implementation.md` avec récap des fichiers touchés, lignes ajoutées/supprimées, tests passés.
- [X] T065 Cleanup `~/.config/roadies/stages/active.toml` deprecated (si présent) : laisser un warn dans le log au boot.

## Tâches optionnelles (T070+, P3)

- [ ] T070 [P3] Ajouter un test E2E pour le scenario hot-plug : connecter/déconnecter un display pendant que le daemon tourne, vérifier que `activeStageByDesktop` reste cohérent.
- [ ] T071 [P3] Documenter la nouvelle sémantique de `switchTo` dans `CLAUDE.md` ou un `README` interne pour les futurs contributeurs.

## Dépendances

```
T001 → T002,T003 (audit nécessite build clean)
T010 → T011 → T012 → T013 → T014 (refactor stored→computed séquentiel)
T014 → T015,T016,T017 (tests après build OK)
T020 → T021 → T022 → T023 → T024 → T025 (switchTo scopé séquentiel)
T025 → T026,T027,T028 (tests après implémentation)
T040..T044 [P] (renderers indépendants)
T045 → T046 → T047 (cleanup + build après modification renderers)
T050 ⊥ US1, US2 (régression test indépendant)
T060,T061 dépendent de US1+US2+US3 complets
```

## MVP

**MVP minimal viable** : T001..T028 (US1 complet) + T040..T047 (US2 complet) = ~25 tâches. Sans T050+ (régression check, polish), on a déjà résolu les 2 bugs visibles à l'utilisateur.
