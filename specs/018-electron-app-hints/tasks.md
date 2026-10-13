# Tasks: Lettres d'accès dans les applications Electron

**Input**: `specs/018-electron-app-hints/` (spec.md, plan.md, research.md, data-model.md, contracts/app-scan-event.md, reuse-audit.md)
**Tests**: oui. Les décisions pures sont testées avant leur implémentation. Le parcours AX réel se vérifie par l'événement `targets.app_scan` et le test manuel dans T3 Code.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: User Story 1 - Des lettres dans les applications Electron (Priority: P1) 🎯 MVP

**Goal**: Roadie demande à l'application Electron de publier son arbre, puis relance le parcours tant que l'arbre est vide, dans une attente bornée.

**Independent Test**: tests unitaires de la politique de relance et de la détection Electron ; puis T3 Code au premier plan, double Commande, plus de 10 lettres.

- [x] T001 [US1] Écrire les tests de `AppTargetQueryService.shouldRetryScan(isElectron:sawWebArea:exploredFully:retries:)` (règle corrigée après la mesure de T011) et `AppTargetQueryService.isElectronBundle(at:)` (dossier temporaire avec et sans `Contents/Frameworks/Electron Framework.framework`) dans `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`. Résultat observable : les tests échouent à la compilation tant que les fonctions n'existent pas.
- [x] T002 [US1] Implémenter `shouldRetryScan` et `isElectronBundle(at:)` en fonctions statiques de `AppTargetQueryService` dans `Sources/RoadieDaemon/AppTargetQueryService.swift`. Résultat observable : T001 passe.
- [x] T003 [US1] Dans `LiveAppTargetProvider.candidates` (`Sources/RoadieDaemon/AppTargetQueryService.swift`) : quand le boost est effectif, lire puis poser `AXManualAccessibility` sur l'élément application ; extraire le parcours en une fonction privée ; relancer après 150 ms tant que `shouldRetryScan` est vrai ; ne jamais remettre l'attribut à faux (FR-004). Résultat observable : build OK ; comportement vérifié en T011.

**Checkpoint**: le parcours d'une application Electron trouve son contenu.

---

## Phase 2: User Story 2 - Seulement des lettres utiles et cliquables (Priority: P2)

**Goal**: aucun élément hors du cadre de la fenêtre ne reçoit de lettre.

**Independent Test**: test unitaire sur des cadres dans, à cheval et hors de la fenêtre.

- [x] T004 [US2] Écrire les tests de `AppTargetQueryService.visibleFrame(_:in:)` (élément dedans, à cheval rogné avec point de clic dans la fenêtre, dehors, cadre de fenêtre absent ; renommé après contre-revue) dans `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`.
- [x] T005 [US2] Implémenter `visibleFrame(_:in:)` et l'appliquer dans le parcours de `LiveAppTargetProvider`, en comptant les éléments écartés, dans `Sources/RoadieDaemon/AppTargetQueryService.swift`. Résultat observable : T004 passe.

---

## Phase 3: User Story 3 - Un parcours mesurable (Priority: P2)

**Goal**: chaque parcours écrit `targets.app_scan` selon `contracts/app-scan-event.md`.

**Independent Test**: un fournisseur factice rend des statistiques ; `TargetHintService.list` écrit l'événement avec les mêmes valeurs dans un journal temporaire.

- [x] T006 [US3] Écrire le test « list écrit targets.app_scan quand le rapport porte des statistiques, et ne l'écrit pas sinon » dans `Tests/RoadieDaemonTests/TargetHintServiceTests.swift`.
- [x] T007 [US3] Ajouter `AppTargetScanStats` (champs de `data-model.md`) et le champ optionnel `scan` à `AppTargetQueryReport` ; remplir les statistiques dans `LiveAppTargetProvider` dans `Sources/RoadieDaemon/AppTargetQueryService.swift`.
- [x] T008 [US3] Écrire l'événement `targets.app_scan` dans `TargetHintService.list` dans `Sources/RoadieDaemon/TargetHintService.swift`. Résultat observable : T006 passe.

---

## Phase 4: Polish & vérification

- [x] T009 [P] Documenter le comportement Electron (demande de publication, première session plus lente, désactivation par `ax_boost_enabled`, lecture de `targets.app_scan`) dans `docs/fr/features.md` et `docs/en/features.md`.
- [x] T010 Lancer `./scripts/test` (suite complète) et `./scripts/with-xcode swift build`. Résultat observable : 0 échec, build OK.
- [x] T011 Installer et relancer (`make install`, `make restart`), puis mesurer dans T3 Code selon `quickstart.md`. Consigner les valeurs de `targets.app_scan` (T3 Code et une application native) dans `specs/018-electron-app-hints/implementation.md`. Résultat observable : `isElectron=true`, `candidates` > 10 dans T3 Code (SC-001), attente ajoutée ≤ 300 ms à la première session (SC-004) ; `retries=0` et `elapsedMs` ≤ `timeout_ms` dans l'application native (SC-003). Validation utilisateur : la lettre d'un fil de la barre latérale ouvre ce fil (SC-002).
- [x] T012 Régler `max_depth` et `timeout_ms` dans `~/.config/roadies/roadies.toml` d'après la mesure de T011, et consigner la décision chiffrée dans `implementation.md`. Résultat observable : nouvelle mesure avec `stopReason` et nombre de cibles meilleurs ou égaux.

---

## Dependencies & Execution Order

- T001 → T002 → T003 (même fichier).
- T004 → T005 après T003 (même fichier, même fonction de parcours).
- T006 avant T008 ; T007 après T005 (même fichier) ; T008 après T007.
- T009 indépendante.
- T010 après T001-T009 ; T011 après T010 ; T012 après T011.

## Convergence

- [x] T013 [US1] Écart à AS1.1 et SC-004 : la toute première session après la demande de publication ne voit que la fenêtre (mesures T3 Code 21:01:36Z et draw.io, `implementation.md`). Disjoncteur Article IV déclenché après 3 tentatives (règle v1, règle v2, demande à l'activation). Décision utilisateur requise : accepter la limite et amender AS1.1/SC-004, ou poursuivre l'investigation. **Décision 2026-10-13 : limite acceptée, AS1.1 et SC-004 amendés, piste capturée dans la boîte à idées.**
