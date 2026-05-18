# Tasks: Roadie Target Mode

**Input**: Design documents from `/specs/009-roadie-target-mode/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/
**Tests**: Tests unitaires Swift requis pour les services purs et contrats JSON.
**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Mettre en place les artefacts et le contexte projet.

- [x] T001 Update SpecKit agent context in AGENTS.md for specs/009-roadie-target-mode
- [x] T002 [P] Add target-mode CLI contract documentation in specs/009-roadie-target-mode/contracts/target-mode-cli.md

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Modèles et utilitaires partagés par toutes les user stories.

- [x] T003 [P] Add target model structs in Sources/RoadieDaemon/TargetHintService.swift
- [x] T004 [P] Add deterministic label generator tests in Tests/RoadieDaemonTests/TargetHintServiceTests.swift
- [x] T005 Implement deterministic label generator and text normalization in Sources/RoadieDaemon/TargetHintService.swift
- [x] T006 Add formatter support for target reports in Sources/RoadieDaemon/Formatters.swift
- [x] T007 Add target configuration defaults in Sources/RoadieCore/Config.swift

**Checkpoint**: Le modèle de cible et les labels sont disponibles pour les histoires.

---

## Phase 3: User Story 1 - Lister et inspecter les cibles Roadie (Priority: P1)

**Goal**: Lister les stages, fenêtres, displays, desktops et bookmarks connus de Roadie avec labels et diagnostics.

**Independent Test**: Un test construit un snapshot simulé et vérifie les cibles Roadie produites.

### Tests for User Story 1

- [x] T008 [P] [US1] Add Roadie target listing tests in Tests/RoadieDaemonTests/TargetHintServiceTests.swift
- [x] T009 [P] [US1] Add inspection tests in Tests/RoadieDaemonTests/TargetInspectionServiceTests.swift

### Implementation for User Story 1

- [x] T010 [US1] Implement Roadie target listing in Sources/RoadieDaemon/TargetHintService.swift
- [x] T011 [US1] Implement target inspection service in Sources/RoadieDaemon/TargetInspectionService.swift
- [x] T012 [US1] Expose `roadie targets list|inspect` in Sources/roadie/main.swift
- [x] T013 [US1] Expose `roadie query targets` in Sources/RoadieDaemon/AutomationQueryService.swift and Sources/roadie/main.swift

**Checkpoint**: Les cibles Roadie sont listables et inspectables en texte et JSON.

---

## Phase 4: User Story 2 - Activer une cible Roadie par label ou recherche (Priority: P1)

**Goal**: Résoudre un label ou filtre et déclencher une action Roadie sûre.

**Independent Test**: Les tests vérifient résolution, ambiguïté, cible périmée et mapping d'actions.

### Tests for User Story 2

- [x] T014 [P] [US2] Add target resolution tests in Tests/RoadieDaemonTests/TargetHintServiceTests.swift

### Implementation for User Story 2

- [x] T015 [US2] Implement target resolver and stale target errors in Sources/RoadieDaemon/TargetHintService.swift
- [x] T016 [US2] Implement `roadie targets activate` dispatch in Sources/roadie/main.swift
- [x] T017 [US2] Add structured target events in Sources/RoadieDaemon/TargetHintService.swift

**Checkpoint**: Un label ou ID peut focaliser/switcher/envoyer vers une cible Roadie.

---

## Phase 5: User Story 3 - Exposer des zones sensibles applicatives (Priority: P2)

**Goal**: Lister les éléments applicatifs AX de manière expérimentale, bornée et isolée.

**Independent Test**: Tests sur provider simulé, limites et disabled-by-default.

### Tests for User Story 3

- [x] T018 [P] [US3] Add app target provider tests in Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift

### Implementation for User Story 3

- [x] T019 [US3] Implement app target query abstractions in Sources/RoadieDaemon/AppTargetQueryService.swift
- [x] T020 [US3] Integrate app target inclusion in Sources/RoadieDaemon/TargetHintService.swift
- [x] T021 [US3] Add CLI guards for `--source app|all` in Sources/roadie/main.swift

**Checkpoint**: Les app targets peuvent être demandés explicitement sans modifier le layout.

---

## Phase 6: User Story 4 - Préparer l'overlay de hints Roadie (Priority: P2)

**Goal**: Préparer la couche runtime pour l'overlay en s'appuyant sur les mêmes cibles.

**Independent Test**: Vérifier que les commandes de runtime retournent les labels à afficher et respectent l'expiration.

### Implementation for User Story 4

- [x] T022 [US4] Add `roadie targets show|hide` runtime command skeleton in Sources/roadie/main.swift
- [x] T023 [US4] Document overlay follow-up boundaries in specs/009-roadie-target-mode/quickstart.md

**Checkpoint**: La base overlay est contractée sans perturber le rail existant.

---

## Phase 7: User Story 5 - Fournir un inspecteur orienté debug et agent (Priority: P1)

**Goal**: Donner une explication exploitable par humain et agent pour chaque cible.

**Independent Test**: Inspection de fenêtres pinées, flottantes, non tileables et stages.

### Implementation for User Story 5

- [x] T024 [US5] Extend inspection reasons for tileability, pin, focus and scope in Sources/RoadieDaemon/TargetInspectionService.swift
- [x] T025 [US5] Add JSON contract tests for inspection output in Tests/RoadieDaemonTests/TargetInspectionServiceTests.swift

**Checkpoint**: `targets inspect` explique les décisions Roadie.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Validation, documentation et cohérence.

- [x] T026 [P] Update French and English docs in docs/fr/cli.md and docs/en/cli.md
- [x] T027 [P] Update feature docs in docs/fr/features.md and docs/en/features.md
- [x] T028 Run `swift test` and fix failures
- [x] T029 Run `make build`
- [x] T030 Update spec status and task counters in specs/009-roadie-target-mode/spec.md

---

## Phase 9: User Story 6 - Picker clavier par recherche (Priority: P1)

**Goal**: Resoudre une requete texte ou un label et activer une cible unique sans mutation en cas d'ambiguite.

**Independent Test**: Un test pur verifie selection unique, ambiguite et absence de resultat d'action quand plusieurs candidates existent.

- [x] T031 [P] [US6] Add target picker tests in Tests/RoadieDaemonTests/TargetHintServiceTests.swift
- [x] T032 [US6] Add TargetPickResult and picker resolution in Sources/RoadieDaemon/TargetHintService.swift
- [x] T033 [US6] Expose `roadie targets pick` in Sources/roadie/main.swift
- [x] T034 [US6] Add target picker text formatter in Sources/RoadieDaemon/Formatters.swift

---

## Phase 10: User Story 7 - Actions enrichies sur cibles (Priority: P2)

**Goal**: Ajouter les actions app target double-click/right-click et corriger le focus bookmark via Target Mode.

**Independent Test**: Les tests verifient que le provider recoit le bon type de clic et que les actions non supportees restent refusees.

- [x] T035 [P] [US7] Add app target action tests in Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift
- [x] T036 [US7] Extend TargetActionVerb with `double-click` and `right-click` in Sources/RoadieDaemon/TargetHintService.swift
- [x] T037 [US7] Route app click variants through AppTargetQueryService in Sources/RoadieDaemon/AppTargetQueryService.swift
- [x] T038 [US7] Route bookmark focus through WindowBookmarkCommandService in Sources/RoadieDaemon/TargetHintService.swift

---

## Phase 11: User Story 8 - Mode labels-only et integration raccourcis (Priority: P2)

**Goal**: Exposer un etat overlay/labels-only stable pour les raccourcis et futurs overlays.

**Independent Test**: `targets show --json` retourne les memes labels que `targets list` et `targets hide` reste idempotent.

- [x] T039 [P] [US8] Add TargetOverlayState tests in Tests/RoadieDaemonTests/TargetHintServiceTests.swift
- [x] T040 [US8] Add TargetOverlayState model in Sources/RoadieDaemon/TargetHintService.swift
- [x] T041 [US8] Update `targets show|hide` JSON behavior in Sources/roadie/main.swift

---

## Phase 12: User Story 9 - Inspecteur renforce pour agents (Priority: P2)

**Goal**: Rendre l'inspecteur et les contrats plus explicites pour les agents.

**Independent Test**: Le JSON expose les actions supportees et les erreurs de resolution retournent les candidates.

- [x] T042 [P] [US9] Add JSON contract tests for picker ambiguity in Tests/RoadieDaemonTests/TargetHintServiceTests.swift
- [x] T043 [US9] Ensure target inspection and picker outputs include supported actions in Sources/RoadieDaemon/TargetInspectionService.swift and Sources/RoadieDaemon/TargetHintService.swift

---

## Phase 13: User Story 10 - Navigation applicative future bornee (Priority: P3)

**Goal**: Documenter explicitement les limites non livrees et garder les app targets experimentales isolees.

**Independent Test**: La configuration par defaut garde les app targets desactivees et la documentation annonce les limites.

- [x] T044 [P] [US10] Add docs for non-delivered Vimac/Homerow features in docs/fr/features.md and docs/en/features.md
- [x] T045 [US10] Update app target config docs in docs/fr/cli.md and docs/en/cli.md

---

## Phase 14: Analyse, validation et statut

- [x] T046 Run speckit analysis and fix unambiguous artifact issues
- [x] T047 Run `./scripts/with-xcode swift test`
- [x] T048 Run `make build`
- [x] T049 Update spec status and counters in specs/009-roadie-target-mode/spec.md
- [x] T050 Add implementation REX in specs/009-roadie-target-mode/implementation.md

---

## Phase 15: Configurabilite fine des capacites Target Mode

**Goal**: Permettre aux utilisateurs de couper separement les capacites inspirees de Vimac/Homerow.

**Independent Test**: Les tests valident les valeurs par defaut, le decodage TOML et les refus explicites sans mutation.

- [x] T051 Add `[experimental.target_mode]` config model and validation in Sources/RoadieCore/Config.swift
- [x] T052 [P] Add target mode config tests in Tests/RoadieDaemonTests/ConfigTests.swift
- [x] T053 Add target-mode, picker and app-mouse-action guards in Sources/RoadieDaemon/TargetHintService.swift
- [x] T054 [P] Add target service tests for disabled target mode, disabled picker and disabled app mouse actions in Tests/RoadieDaemonTests/TargetHintServiceTests.swift
- [x] T055 Update FR/EN docs and CLI contract for target-mode configuration
- [x] T056 Run targeted config and target tests

---

## Phase 16: User Story 11 - Grille récursive multi-écran

**Goal**: Ajouter une grille récursive actionnable et exploitable par humain/agent.

- [x] T057 [P] [US11] Add target grid config defaults and TOML decoding in Sources/RoadieCore/Config.swift
- [x] T058 [P] [US11] Add deterministic grid geometry tests in Tests/RoadieDaemonTests/TargetGridServiceTests.swift
- [x] T059 [US11] Implement TargetGridService reports, paths and RoadieTarget conversion in Sources/RoadieDaemon/TargetGridService.swift
- [x] T060 [US11] Add grid overlay tint and inspection support in Sources/RoadieDaemon/TargetOverlayPresenter.swift and Sources/RoadieDaemon/TargetInspectionService.swift

---

## Phase 17: User Story 12 - Actions souris sur grille

**Goal**: Rendre la grille directement actionnable.

- [x] T061 [US12] Expose `roadie grid show|click|double-click|right-click|move|scroll-up|scroll-down|drag` in Sources/roadie/main.swift
- [x] T062 [US12] Implement grid mouse, scroll and drag posting in Sources/RoadieDaemon/TargetGridService.swift

---

## Phase 18: User Story 13/14 - Record/replay enrichi

**Goal**: Enregistrer et rejouer des macros avec contexte de cible et fallback grille.

- [x] T063 [P] [US13] Add macro model round-trip and nearest-target tests in Tests/RoadieDaemonTests/TargetMacroServiceTests.swift
- [x] T064 [US13] Implement TargetMacroService recording models, event tap capture and JSON persistence in Sources/RoadieDaemon/TargetMacroService.swift
- [x] T065 [US14] Implement replay with target-first and coordinate fallback in Sources/RoadieDaemon/TargetMacroService.swift
- [x] T066 [US13] Expose `roadie record start|replay|list|inspect|delete` in Sources/roadie/main.swift

---

## Phase 19: User Story 15 - AX boost Firefox/Electron

**Goal**: Améliorer la découverte des zones applicatives sans relayout.

- [x] T067 [US15] Add AX boost config and validation in Sources/RoadieCore/Config.swift
- [x] T068 [US15] Traverse visible/navigation/rows/columns/contents/tabs AX attributes with dedup and max depth in Sources/RoadieDaemon/AppTargetQueryService.swift

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Blocks all user stories.
- **US1 / US5**: Start after foundational, required before polished agent usage.
- **US2**: Depends on US1 target listing.
- **US3**: Depends on foundational and US1 source selection.
- **US4**: Depends on foundational target model.
- **Polish**: Depends on selected user stories complete.

### Parallel Opportunities

- T002, T003, T004 can run independently.
- Tests T008/T009/T014/T018 can be prepared before implementation.
- Docs T026/T027 can run after CLI surface is stable.

## Implementation Strategy

1. Complete foundational target model.
2. Deliver CLI/JSON list and inspect.
3. Add safe activation.
4. Add isolated app targets.
5. Add picker, overlay-state and enriched app actions.
6. Add grid, record/replay and AX boost as independently configurable experimental surfaces.
7. Document BTT/Karabiner integration boundaries and non-delivered future features.
8. Run tests/build and update status.
