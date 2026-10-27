# Tâches 092 - Vue Grille des workflows

## Phase 1 - Modèle et moteur (US1, P1)
- [x] T001 [US1] Tests d'abord dans `Tests/RoadieDaemonTests/Spec092GridTests.swift` : construction
  des tuiles (JSON avec `preselect`, liste de chemins avec image et non-image, colonnes bornées),
  brique Grille par script et par argument (effet `showGrid` noté), surcharge `columncount` par une
  brique JSON, déclencheur `externalid` sur une brique JSON. Résultat observable : tests en échec.
- [x] T002 [US1] `AlfredObject.externalID` lu de `inboundconfig.externalid` dans
  `Sources/RoadieDaemon/AlfredWorkflow.swift` ; `preselect` lu dans
  `Sources/RoadieDaemon/AlfredScriptFilterResponse.swift`.
- [x] T003 [US1] `Sources/RoadieDaemon/AlfredGridView.swift` : vue et construction pure (FR-002,
  FR-003, FR-007) ; genre `.grid` dans `AlfredWorkflowIndex.swift`.
- [x] T004 [US1] Moteur (`AlfredWorkflowEngine.swift`) : brique `userinterface.grid`, effet
  `showGrid`, surcharge `config` portée par `Step.next` (FR-001, FR-008), `externalTrigger` par
  `externalid` et exécution de la brique visée (FR-009) ; `RecordedEffects.showGrid` dans
  `Spec088Support.swift`. Résultat observable : T001 réussit.

## Phase 2 - Barre en grille (US2, P1)
- [x] T005 [US2] Tests : `SearchBarLayout.makeGrid` (tuiles par rangée, défilement qui garde la
  sélection, clic sur une tuile), `SearchInputPanel.navigation` (← → `.move` en grille seulement),
  calcul du voisin (rang ± 1, ± colonnes, espaceurs sautés, bords).
- [x] T006 [US2] `SearchBarRenderer.swift` : `TargetSearchBar.grid`, `makeGrid`, dessin d'une tuile et
  du pied (FR-003).
- [x] T007 [US2] `SearchInputPanel.swift` + `SearchKeyInput.Kind.move` : ← → dans une grille (FR-004).
- [x] T008 [US2] Barre (`TargetOverlayPresenter.swift`, `LauncherSearchContext.swift`) : vue reçue,
  lignes `.workflowItem` filtrées (FR-005), présélection (FR-007), navigation 2D (FR-004), Retour avec
  les variables de la vue (FR-006), Échap ferme. Résultat observable : T005 réussit.
- [x] T009 [US2] Effet réel : `AlfredLiveEffects.showGrid`, vue en attente et barre rouverte dans
  `TargetModeRuntimeController.swift` ; `externalTrigger` utilisé par `roadie workflow trigger`.

## Phase 3 - Fiche, mesure, livraison (US3, P2)
- [x] T010 [US3] `userinterface.grid` géré par la fiche (FR-010) ; test de la fiche.
- [x] T011 [US3] Suite complète `scripts/test --no-parallel` ; `roadie workflow check` sur le corpus
  `/tmp/roadie-wf-corpus/mixed2` comparé à la mesure de la 089 (92/102 entrée complète, 79/102 entiers).
- [x] T012 [US3] Documentation FR/EN (`docs/fr/features.md`, `docs/en/features.md`), CHANGELOG,
  `validation.md` (tests, mesure, limites, essai utilisateur).

## Analyse (27 octobre 2026)
Voir `specs/093-ordres-alfred/tasks.md` (analyse commune). Pour la 092 : couverture 10/10 ; Tab dans
une grille garde le rôle actuel des lignes de workflow (vérifié à l'implémentation, T008).

## Convergence
- [x] T013 [US3] Fiche (`AlfredCompatibility.swift`) : une Grille de source inconnue est nommée
  `userinterface.grid:inputtype:N`, une Grille dont le script `inputfile` manque ou n'est pas
  exécutable est signalée comme un script absent (FR-002, FR-010) ; test dans `Spec092GridTests`.
Converge : passage 1, 1 tâche ajoutée (T013, faite) ; passage 2 : CONVERGED.
