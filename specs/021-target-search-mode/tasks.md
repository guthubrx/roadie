# Tasks: Mode recherche du mode lettres

**Input**: `specs/021-target-search-mode/` (spec, plan, research, data-model, contracts/search-mode.md, reuse-audit)
**Tests**: modèle de recherche et analyse du raccourci testés avant implémentation ; affichage et raccourci global vérifiés par mesure et test manuel.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Fondations

- [x] T001 [US4] Rendre `normalizedKey` partagé dans `Sources/RoadieCore/Config.swift` (alias `ctrl`→`control`, `hyper`→`command+control+alt`) ; ajouter `searchHotkey` (`search_hotkey`, défaut `"command+control+alt+f"`) à `TargetModeConfig` (init, CodingKeys, décodage), à `knownKeys`, et une validation (chaîne vide = désactivé ; sinon au moins un modificateur et une touche). Tests dans `Tests/RoadieDaemonTests/ConfigTests.swift`. Résultat observable : `roadie config validate` accepte le défaut et refuse `"f"`.

---

## Phase 2: User Story 1 - Recherche (Priority: P1) 🎯 MVP

- [x] T002 [US1] Écrire `Tests/RoadieDaemonTests/TargetSearchModelTests.swift` : correspondance sans casse/accents/espaces (« watchlater » trouve « Watch Later ») ; titres commençant par la requête d'abord ; requête vide, `*`, `;` = toutes ; mise en avant à 0 après frappe ; suivante/précédente en boucle ; saut par label ; aucune correspondance.
- [x] T003 [US1] Implémenter `Sources/RoadieDaemon/TargetSearchModel.swift`. Résultat observable : T002 passe.
- [x] T004 [US1] Rattacher le texte des `AXStaticText` descendants au plus proche candidat web (index porté par la pile) dans un champ `searchText` distinct de `title`, gardé seulement pour les candidats sans autre candidat descendant, 500 caractères max, sans répéter titre/valeur ; `matchText` l'inclut ; dans `Sources/RoadieDaemon/AppTargetQueryService.swift` ; test de la fonction pure d'ajout dans `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`.
- [x] T005 [US1] Décodage propre à la recherche `SearchKeyInput` (`Sources/RoadieDaemon/TargetOverlayPresenter.swift`) : caractères bruts (lettres, chiffres, espace, `*`, `;`, `?`), Tab/Maj-Tab, Ctrl-N/Ctrl-P, flèches, Retour avec Maj/Cmd et répétition automatique, Échap, Effacement ; touches mortes ignorées ; `KeyInput` des modes lettres et grille inchangé.
- [x] T006 [US1] Session `TargetSearchSession` dans `Sources/RoadieDaemon/TargetOverlayPresenter.swift` : tap clavier, modèle, filtrage des étiquettes affichées, mise en avant verte, barre de saisie en bas de l'écran qui contient le pointeur (requête, nombre de correspondances, visible sans correspondance), Échap, fermeture après 60 s sans frappe, Retour différé annulé à la fermeture, activation de la cible figée via `TargetHintService.perform` ; `TargetOverlayView` dessine comme avant sans état de recherche.
- [x] T007 [US1] Commande `targets.search` dans `Sources/RoadieDaemon/TargetModeRuntimeController.swift` (toutes sources, cibles app incluses, 500 résultats max ; pression ignorée si une recherche est ouverte) et `roadie targets search [--duration N]` dans `Sources/RoadieDaemon/CLICommandRouter.swift`. Résultat observable : la commande ouvre la recherche.

---

## Phase 3: User Story 4 - Raccourci global paramétrable (Priority: P1)

- [x] T008 [US4] Écrire `Tests/RoadieDaemonTests/TargetSearchHotkeyTests.swift` : analyse `"command+control+alt+f"` → modificateurs Carbon + caractère ; noms `space`, `return`, `f1` ; refus sans modificateur ; chaîne vide = désactivé.
- [x] T009 [US4] Implémenter `Sources/RoadieDaemon/TargetSearchHotkey.swift` : traduction caractère (sans modificateur) → code physique par la disposition active (`UCKeyTranslate`, masque sans touches mortes, `LMGetKbdType`), `RegisterEventHotKey` exclusif / `UnregisterEventHotKey` sur le fil principal, relecture toutes les 2 s qui compare le code résolu et les drapeaux `enabled`/`overlay_enabled`, événement `target_mode.search_hotkey` ; démarrage et arrêt avec le composant mode lettres dans `Sources/roadied/main.swift`. Résultat observable : T008 passe ; Hyper+F ouvre la recherche ; changer la clé prend effet sans redémarrage.

---

## Phase 4: User Story 2 - Variantes de clic (Priority: P2)

- [ ] T010 [US2] Ajouter `command-click` à `TargetActionVerb` (`Sources/RoadieDaemon/TargetHintService.swift`) et le Cmd-clic à `AppTargetQueryService.click` ; dans le modèle : Retour = action par défaut, Maj = clic droit, Cmd = Cmd-clic, deux Retour en moins de 0,35 s = double-clic ; tests dans `TargetSearchModelTests.swift`.

---

## Phase 5: User Story 3 - Tout afficher et propriétés (Priority: P3)

- [ ] T011 [US3] `?` : la barre affiche rôle, titre, valeur, id de la cible mise en avant jusqu'à la frappe suivante (modèle + affichage) ; test du modèle.

---

## Phase 5b: Toutes les fenêtres visibles (ajout du 2026-10-13)

- [x] T015 [US1] Point de clic des feuilles web : premier `AXImage`/`AXStaticText` visible du candidat (`clickFrame`), dans `Sources/RoadieDaemon/AppTargetQueryService.swift` et `RoadieTarget` ; test dans `AppTargetQueryServiceTests.swift`. Validé par l'utilisateur dans l'Historique Bluejay (double Commande et Hyper+F).
- [ ] T016 [US1] Portée `visible_windows` dans `LiveAppTargetProvider` : fenêtres à l'écran (CG, couche 0, de l'avant vers l'arrière), élément AX par numéro de fenêtre (`RoadieAX`), parcours parallèles avec l'échéance commune, retrait des éléments cachés par une fenêtre de devant, `scope.windowId` sur chaque cible, statistiques par fenêtre. `scope` accepte `visible_windows` (validation de la config). Tests des fonctions pures (occlusion).
- [ ] T017 [US1] Le mode recherche utilise `visible_windows` ; le clic d'une cible d'une autre fenêtre la focalise d'abord (`WindowCommandService.focus`), attend l'application active, puis clique. Résultat observable : Hyper+F trouve et active un élément d'une fenêtre non active.

## Phase 6: Polish & vérification

- [ ] T012 [P] Documenter le mode recherche et `search_hotkey` dans `docs/fr/features.md`, `docs/en/features.md`, `examples/roadies.toml`.
- [ ] T013 `./scripts/test` (suite complète) et `./scripts/with-xcode swift build`. Résultat observable : 0 échec.
- [ ] T014 Installer (`make install`, `make restart`), mesurer et faire valider : Hyper+F dans Bluejay (« subscr » + Retour, titre de vidéo, Maj-Retour, Cmd-Retour), T3 Code et Finder (mode lettres classique inchangé : 150 et 58), changement de `search_hotkey` à chaud. Consigner dans `specs/021-target-search-mode/implementation.md`.

## Dependencies & Execution Order

- T001 avant T008-T009. T002 → T003. T005 → T006 → T007. T003 + T006 + T009 avant T010-T011. T012 indépendante. T013 après tout le code ; T014 après T013.
