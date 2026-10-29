# Tâches 131 - actions Alfred et Alfred 6

Format : `- [ ] Tnnn [Pn] [USn] description (fichiers) - vérification`. Tests avant code quand le risque le justifie.

## Phase 1 - Socle

- [x] T001 [P1] Étendre `LauncherSubject` (`.text`), `LauncherVerb` (verbes de fichier, texte, onglet, application) et
  `LauncherDestination.Kind` (`.folder`, `.application`, `.tag`) avec noms FR/EN et `needsDestination`
  (`Sources/RoadieDaemon/LauncherActions.swift`) - compilation, `LauncherVerb.names` couvrent tous les cas.

## Phase 2 - US1 Fichiers (P1)

- [x] T002 [P1] [US1] Tests des opérations de fichier sur dossiers temporaires : copier vers, déplacer vers, refus si
  le nom existe, « en remplaçant » (ancien à la corbeille), corbeille, alias, informations (type, taille, dates,
  SHA-256), étiquettes (`Tests/RoadieDaemonTests/Spec131FileOperationsTests.swift`) - échouent avant T003.
- [x] T003 [P1] [US1] `LauncherFileOperations` : opérations pures et sûres, une ou plusieurs sources
  (`Sources/RoadieDaemon/LauncherFileOperations.swift`) - T002 réussit.
- [x] T004 [P1] [US1] Verbes de fichier proposés (`LauncherVerb.verbs(for: .file)`) et en sélection multiple
  (`LauncherSelection.swift`) ; destinations dossiers (récents, favoris, Spotlight) et applications
  (`LauncherActions.swift`, `TargetOverlayPresenter.swift`) - test : la liste des verbes d'un fichier et d'un dossier.
- [x] T005 [P1] [US1] Exécution dans `performFile` : copier dans le presse-papiers, copier/déplacer (avec et sans
  remplacement), ouvrir avec, e-mail, corbeille, alias, informations (lignes copiables), étiquettes, parcourir,
  terminal ici, contenu du paquet (`TargetModeRuntimeController.swift`) - test d'exécution sur fichier temporaire.

## Phase 3 - US2 Texte (P1)

- [x] T006 [P1] [US2] Tests : extraction des adresses web et e-mail, verbes d'un texte et d'une adresse, actions
  universelles texte/adresse proposées (`Tests/RoadieDaemonTests/Spec131TextTests.swift`).
- [x] T007 [P1] [US2] `LauncherText` : adresses détectées, verbes copier, chercher sur le web, ouvrir l'adresse,
  extraire, e-mail, afficher en grand (`Sources/RoadieDaemon/LauncherText.swift`) - T006 réussit.
- [x] T008 [P1] [US2] Texte tapé : Tab sur la ligne « Texte » de repli ouvre ses verbes ; Capslock + Maj + F avec une
  sélection ouvre les verbes du texte sélectionné (`TargetOverlayPresenter.swift`, `TargetModeRuntimeController.swift`)
  - test du choix sélection/fenêtre active.
- [x] T009 [P1] [US2] Actions universelles des workflows comme verbes des textes, adresses et fichiers (un ou
  plusieurs), lancées avec l'élément (`TargetOverlayPresenter.swift`, `AlfredWorkflowIndex.swift`) - test.

## Phase 4 - US3 Onglets (P2)

- [x] T010 [P2] [US3] Verbes d'onglet : fermer, copier l'adresse, nouvelle fenêtre ; scripts Safari et Chromium,
  Firefox par `FirefoxTabSelector` + ⌘W et `--new-window` (`LauncherOpenItems.swift`, `TargetModeRuntimeController.swift`,
  `Tests/RoadieDaemonTests/Spec131TabTests.swift`) - test des scripts produits et des verbes proposés.

## Phase 5 - US4 Modificateurs (P2)

- [x] T011 [P2] [US4] Réglages `return_cmd`, `return_alt`, `return_ctrl` (config, catalogue des paramètres FR/EN,
  `LauncherVariant.of`) ; défauts identiques à aujourd'hui (`RoadieCore/Config.swift`, `SettingsCatalog*.swift`,
  `LauncherActions.swift`, `Tests/RoadieDaemonTests/Spec131ReturnModifiersTests.swift`) - test des défauts et d'un choix.

## Phase 6 - US5 Briques de workflow (P2)

- [x] T012 [P2] [US5] Tests : tables des commandes système et Musique (numéros de research R2, R3, inconnu refusé),
  dictionnaire, applications ouvertes (`Tests/RoadieDaemonTests/Spec131WorkflowObjectsTests.swift`).
- [x] T013 [P2] [US5] `AlfredSystemObjects` : commandes système (avec confirmation), Musique, définition du
  dictionnaire, applications ouvertes filtrées (`Sources/RoadieDaemon/AlfredSystemObjects.swift`) - T012 réussit.
- [x] T014 [P2] [US5] Branchement dans le moteur (`action.systemcommand`, `action.itunescommand`) et comme entrées
  de la barre (`input.dictionaryfilter`, `input.runningappsfilter`), compatibilité marquée complète
  (`AlfredWorkflowEngine.swift`, `AlfredWorkflowIndex.swift`, `AlfredCompatibility.swift`, `TargetOverlayPresenter.swift`)
  - test d'exécution d'un workflow de chaque type.

## Phase 7 - US6 Barre sans workflow (P2)

- [x] T015 [P2] [US6] Tests puis `LauncherMenuSearch` : parcours borné des menus (logique de chemin et de filtre
  pure, lecture AX à part) ; ligne « Menus » dans la barre, Retour presse l'élément (`Sources/RoadieDaemon/LauncherMenuSearch.swift`,
  `TargetOverlayPresenter.swift`, `TargetModeRuntimeController.swift`, `Tests/RoadieDaemonTests/Spec131MenuSearchTests.swift`) - durée de lecture des menus mesurée sur une
  application réelle (SC-003 : moins de 1 s).
- [x] T016 [P2] [US6] Commandes système ajoutées : mode sombre, capture d'écran (écran, zone, fenêtre), raccourcis Apple
  (liste en cache, lancement), relancer et quitter les autres (verbes d'application) (`LauncherSystemCommands.swift`,
  `TargetModeRuntimeController.swift`, tests dans `Spec131SystemCommandsTests.swift`).
- [x] T017 [P2] [US6] Tâche d'automatisation absente : une mise à jour par processus puis relecture
  (`AlfredWorkflowEngine.swift`, `AlfredAutomationTasks.swift`) - test avec une mise à jour simulée.

## Phase 8 - US7 Alfred 6 (P3)

- [x] T018 [P3] [US7] Tableaux Markdown : bloc tableau (alignements) et rendu (`AlfredTextView.swift`,
  `WorkflowTextPanel.swift`, `Tests/RoadieDaemonTests/Spec131MarkdownTableTests.swift`).
- [x] T019 [P3] [US7] Thèmes de barre Glassy Dark et Glassy Light (`LauncherTheme.swift`) - test de présence et valeurs.
- [x] T020 [P3] [US7] Style des vues de workflow `workflow_view_style` (theme, glassy-dark, flat-dark, glassy-light),
  réglage FR/EN, appliqué aux panneaux Texte, Image, PDF (`WorkflowTextPanel.swift`, `WorkflowMediaPanel.swift`,
  config et catalogue) - test du réglage et rendu hors écran vérifié.
- [x] T021 [P3] [US7] Apps : catégories, filtre, épinglage, grille dans la barre par le mot-clé `apps`
  (`Sources/RoadieDaemon/LauncherAppsGrid.swift`, `TargetOverlayPresenter.swift`, `Tests/RoadieDaemonTests/Spec131AppsGridTests.swift`).
- [x] T022 [P3] [US7] SF Symbols : données CoreGlyphs (noms, catégories, mots-clés, versions), recherche, panneau
  conforme au modèle et au style `workflow_view_style`, mot-clé `symbols`, Retour copie le nom (`Sources/RoadieDaemon/LauncherSymbols.swift`,
  `Tests/RoadieDaemonTests/Spec131SymbolsTests.swift`) - test des données et de la recherche, rendu hors écran vérifié.

## Phase 9 - Finition

- [ ] T023 Documentation FR/EN du lanceur et des fonctions (`docs/fr/launcher.md`, `docs/en/launcher.md`), changelog.
- [ ] T024 Référence Alfred : lignes passées à « Déjà dans Roadie », Snippet et Contact Action gardés « En partie »
  avec la raison, ligne Alfred 6 réécrite (`docs/analyses/2026-10-25-reference-alfred.html`).
- [ ] T025 Textes ajoutés présents en FR et EN (FR-015), suite complète, tests de scripts, installation signée, santé, reçu `specs/131-actions-alfred/validation.md`.
