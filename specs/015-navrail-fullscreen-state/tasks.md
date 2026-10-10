# Tasks: Etat fullscreen dans le navrail

**Input**: Artefacts de `/specs/015-navrail-fullscreen-state/`  
**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/automation-window-presentation.md`, `quickstart.md`

## Phase 1: Setup

- [X] T001 Vérifier que `.specify/feature.json` pointe vers `specs/015-navrail-fullscreen-state`
- [X] T002 Vérifier que `specs/009-roadie-target-mode/plan.md` n'a plus de diff accidentel

## Phase 2: Foundational

- [X] T003 [P] Ajouter le type `WindowPresentationState` et la compatibilité Codable dans `Sources/RoadieCore/AutomationSnapshot.swift`
- [X] T004 [P] Ajouter le signal natif fullscreen best-effort dans `Sources/RoadieAX/SystemSnapshotProvider.swift`
- [X] T005 Créer le resolver partagé `Sources/RoadieDaemon/WindowPresentationStateResolver.swift`

## Phase 3: User Story 1 - Voir une fenêtre maximized dans sa stage (P1)

**Goal**: Une fenêtre maximized reste visible dans le navrail avec une bordure à quatre coins.

**Independent Test**: Un snapshot synthétique avec une fenêtre proche du visibleFrame retourne `maximized`, et le navrail reçoit cet état pour la vignette correspondante.

- [X] T006 [P] [US1] Ajouter les tests `maximized` tolérants dans `Tests/RoadieDaemonTests/WindowPresentationStateResolverTests.swift`
- [X] T007 [US1] Implémenter la détection `maximized` tolérante dans `Sources/RoadieDaemon/WindowPresentationStateResolver.swift`
- [X] T008 [US1] Passer les états de présentation au renderer du rail dans `Sources/RoadieDaemon/RailController.swift`
- [X] T009 [US1] Dessiner la bordure à quatre coins pour `maximized` dans tous les modes visuels du rail dans `Sources/RoadieDaemon/RailController.swift`

## Phase 4: User Story 2 - Distinguer nativeFullscreen (P1)

**Goal**: Une fenêtre native fullscreen est distincte de `maximized` et rendue avec une bordure continue.

**Independent Test**: Un snapshot synthétique avec signal natif fullscreen retourne `nativeFullscreen`, même si la frame est aussi maximized.

- [X] T010 [P] [US2] Ajouter les tests de priorité `nativeFullscreen` dans `Tests/RoadieDaemonTests/WindowPresentationStateResolverTests.swift`
- [X] T011 [US2] Implémenter la priorité `nativeFullscreen` dans `Sources/RoadieDaemon/WindowPresentationStateResolver.swift`
- [X] T012 [US2] Dessiner la bordure continue pour `nativeFullscreen` dans tous les modes visuels du rail dans `Sources/RoadieDaemon/RailController.swift`

## Phase 5: User Story 3 - Parité monolithique et modulaire (P1)

**Goal**: Les deux modes consomment le même état calculé.

**Independent Test**: Le snapshot automation expose le même `presentationState` depuis le service partagé, indépendamment du process consommateur.

- [X] T013 [P] [US3] Ajouter les tests du champ `presentationState` dans `Tests/RoadieDaemonTests/AutomationSnapshotTests.swift`
- [X] T014 [US3] Alimenter `AutomationWindowSnapshot.presentationState` depuis `Sources/RoadieDaemon/AutomationSnapshotService.swift`
- [X] T015 [US3] Supprimer le masquage global du navrail basé uniquement sur `fullscreen-like` dans `Sources/RoadieDaemon/RailController.swift`

## Phase 6: User Story 4 - Ne pas perturber le layout (P2)

**Goal**: La représentation navrail ne génère aucune commande de layout nouvelle.

**Independent Test**: Les tests existants de suppression fullscreen/layout restent verts, et aucune dépendance du resolver n'appelle `applyPlan`.

- [X] T016 [P] [US4] Ajouter ou ajuster un test de non-régression rail/fullscreen dans `Tests/RoadieDaemonTests/PowerUserFocusCommandTests.swift`
- [X] T017 [US4] Vérifier que le resolver et le renderer ne déclenchent aucune commande layout dans `Sources/RoadieDaemon/WindowPresentationStateResolver.swift` et `Sources/RoadieDaemon/RailController.swift`

## Phase 7: Polish & Cross-Cutting

- [X] T018 [P] Mettre à jour `docs/fr/features.md` pour documenter `maximized` et `nativeFullscreen` dans le navrail
- [X] T019 [P] Mettre à jour `docs/en/features.md` avec la même information
- [X] T020 Lancer `./scripts/test --filter WindowPresentationStateResolverTests --filter AutomationSnapshotTests --filter PowerUserFocusCommandTests`
- [X] T021 Lancer `./scripts/test`
- [X] T022 Lancer `./scripts/with-xcode swift build`

## Dependencies

- Phase 2 bloque toutes les user stories.
- US1 et US2 peuvent avancer en parallèle après T005.
- US3 dépend de T005, T007 et T011.
- US4 dépend du rendu US1/US2 et de l'intégration US3.

## Parallel Examples

- T003 et T004 peuvent être faits en parallèle.
- T006 et T010 peuvent être écrits en parallèle.
- T018 et T019 peuvent être faits en parallèle après stabilisation du comportement.

## Implementation Strategy

1. Livrer d'abord le resolver et ses tests.
2. Exposer l'état dans l'automation JSON.
3. Brancher le navrail sur l'état calculé.
4. Vérifier l'absence de relayout induit.
5. Documenter en français et en anglais.
