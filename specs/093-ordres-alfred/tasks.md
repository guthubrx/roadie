# Tâches 093 - Ordres à Alfred traduits par Roadie

## Phase 1 - Traduction (US1, P1)
- [x] T001 [US1] Tests d'abord dans `Tests/RoadieDaemonTests/Spec093BridgeTests.swift` : chaque forme
  du corpus (research R1) traduite, AppleScript et JavaScript, bloc `tell … end tell`, `-e` avec
  guillemets échappés ; texte sans Alfred inchangé ; analyse des options d'`osascript` (`-l`, `-e`
  multiples, `-s`, fichier, arguments). Résultat observable : tests en échec.
- [x] T002 [US1] `Sources/RoadieDaemon/AlfredBridge.swift` : `translate`, `orders`, options
  d'`osascript`, objet JavaScript (FR-001, FR-002). Résultat observable : T001 réussit.

## Phase 2 - Interception et ordres (US2, P1)
- [x] T003 [US2] `AlfredScriptRunner.swift` : types 6 et 7 traduits, `PATH` préfixé, `/usr/bin/osascript `
  remplacé dans un texte qui cite Alfred, exécutable `osascript` écrit à la demande (FR-003) ; tests.
- [x] T004 [US2] `CLICommandRouter.swift` : `roadie workflow alfred` et `roadie workflow osascript`
  (FR-004) ; aide de la commande.
- [x] T005 [US2] Réglages gardés : `AlfredWorkflow.load` et cache de l'index (FR-005) ; tests.
- [x] T006 [US2] Démon : `workflow.alfred` (barre, déclencheur, journal FR-007) dans
  `TargetModeRuntimeController.swift`.

## Phase 3 - Fiche, mesure, livraison (US3, P2)
- [x] T007 [US3] Fiche : ordres trouvés et non traduits (FR-006) dans `AlfredCompatibility.swift` et
  `CLICommandRouter.swift` ; test.
- [x] T008 [US3] Mesure réelle SC-002 (workflow d'essai dans `~/.config/roadies/workflows`, retiré
  ensuite) et corpus SC-003 (`roadie workflow check`).
- [x] T009 [US3] Suite complète, documentation FR/EN, CHANGELOG, `validation.md`.

## Analyse (27 octobre 2026)
Passes A à F appliquées aux deux sessions (`spec.md`, `plan.md`, `research.md`, `data-model.md`,
`tasks.md`). Couverture : 7/7 exigences de la 093 et 10/10 de la 092 ont au moins une tâche.
- F1 (moyen, corrigé) : `reload` décrit comme une écriture dans `data-model.md`, sans écriture dans
  `research.md` R4 ; aligné sur R4.
- F2 (faible, gardé) : FR-009 de la 092 sert aussi `run trigger` de la 093 ; dépendance déclarée.
- Aucun finding critique ; aucune violation de constitution.
Seconde lecture : aucun nouvel écart.

## Convergence
- [x] T010 [US2] FR-007 : `version`, `activate` et `quit` sont traduits en valeurs fixes dans le script
  (aucune commande lancée, donc rien à journaliser) ; FR-007 précisé dans `spec.md` en conséquence.
  Un appel de commande ajouté seulement pour journaliser une constante est écarté (article XIX).
Converge : passage 1, 1 tâche ajoutée (T010, faite) ; passage 2 : CONVERGED.
