# Plan d'implémentation : 131 actions Alfred et Alfred 6

**Branche** : `131-actions-alfred` | **Date** : 2026-10-29 | **Spec** : [spec.md](spec.md)

## Résumé

Compléter les lignes « En partie » de la référence Alfred et reprendre les nouveautés d'Alfred 6 (hors IA,
transformation de texte, Snippet, Contacts). Méthode : étendre la grammaire existante objet → verbe →
destination (SPEC-074) avec un sujet texte, des verbes de fichier et d'onglet et deux familles de destinations
(dossiers, applications) ; ajouter quatre briques au moteur de workflows ; ajouter des commandes système à la
barre ; trois présentations nouvelles (Apps, SF Symbols, menus) ; styles et tableaux Markdown.

## Contexte technique

- **Langage** : Swift 6 (outils SwiftPM 6.0), macOS 14 minimum, arm64.
- **Dépendances** : aucune nouvelle. AppKit, CoreServices (dictionnaire), CryptoKit (SHA-256), UniformTypeIdentifiers,
  Accessibilité (menus), AppleScript par `osascript` (Musique, onglets, mode sombre), `screencapture`, `shortcuts`.
- **Stockage** : épinglages d'Apps dans un fichier du lanceur (`TestEnvironment.launcherFile`) ; réglages dans
  `roadies.toml` (`[experimental.target_mode]`).
- **Tests** : Swift Testing (`scripts/test --no-parallel`), fichiers temporaires pour les verbes de fichier, logique
  pure pour les tables et analyses (commandes, Markdown, extraction d'adresses, symboles, catégories).
- **Contraintes** : rien d'écrasé sans « en remplaçant » ; parcours AX bornés et hors du fil principal ; textes
  FR/EN par `tr` ; aucun journal ne contient de texte de l'utilisateur.
- **Échelle** : 9 184 symboles, quelques centaines d'applications, menus bornés à 2 000 éléments.

## Vérification de la constitution

- **III SpecKit** : spec, plan, tâches, implémentation, convergence et audit dans `specs/131-actions-alfred/`.
- **XVIII Complexité** : filtres de symboles et d'applications O(n) par frappe sur des listes préparées une fois ;
  parcours des menus O(e) borné ; extraction d'adresses O(t). Annotations écrites.
- **XIX Minimalisme** : extension des types existants (`LauncherVerb`, `LauncherDestination`, `LauncherSubject`,
  `LauncherSystemCommand`, `LauncherTheme`, `AlfredMarkdown`, moteur de workflows) ; nouveaux fichiers seulement pour
  des responsabilités distinctes (opérations de fichier, texte, menus, symboles, Apps, briques Alfred système).
- **XX Responsabilité** : chaque table venue d'Alfred garde sa preuve dans `research.md` ; les numéros incertains
  sont refusés plutôt que devinés.
- **Sécurité** : écriture de fichiers seulement sur action explicite ; corbeille au lieu de suppression ; menus
  pressés uniquement sur l'application mémorisée à l'ouverture.

## Structure

```text
specs/131-actions-alfred/   spec, plan, research, data-model, quickstart, reuse-audit, tasks, validation
Sources/RoadieDaemon/
  LauncherActions.swift            verbes, sujets, destinations (étendus)
  LauncherFileOperations.swift     NOUVEAU : copier, déplacer, corbeille, alias, infos, étiquettes (pur, testable)
  LauncherText.swift               NOUVEAU : sujet texte, adresses extraites, verbes de texte
  LauncherMenuSearch.swift         NOUVEAU : menus de l'application active (AX)
  LauncherSymbols.swift            NOUVEAU : données SF Symbols et panneau
  LauncherAppsGrid.swift           NOUVEAU : Apps par catégorie, épinglage
  AlfredSystemObjects.swift        NOUVEAU : commandes système et Musique, dictionnaire, applications ouvertes
  LauncherSystemCommands.swift     mode sombre, captures, raccourcis, relancer, quitter les autres
  LauncherOpenItems.swift          verbes d'onglet
  AlfredWorkflowEngine.swift       quatre briques
  AlfredAutomationTasks.swift      tâche absente téléchargée
  AlfredTextView.swift, WorkflowTextPanel.swift   tableaux Markdown, styles
  WorkflowMediaPanel.swift         styles
  LauncherTheme.swift              thèmes Glassy Dark et Glassy Light
  TargetModeRuntimeController.swift, TargetOverlayPresenter.swift   branchements
  SettingsCatalog*.swift, RoadieCore/Config.swift   réglages
Tests/RoadieDaemonTests/Spec131*Tests.swift
docs/fr|en/launcher.md, docs/analyses/2026-10-25-reference-alfred.html, CHANGELOG.md
```

## Lots

1. Fichiers (US1) : opérations pures puis verbes et destinations dossiers/applications.
2. Texte (US2) : sujet texte, sélection, adresses, actions universelles texte/adresse.
3. Onglets (US3).
4. Modificateurs de Retour (US4).
5. Briques de workflow (US5).
6. Barre sans workflow (US6) : menus, commandes, tâches absentes.
7. Alfred 6 (US7) : Apps, SF Symbols, styles et thèmes, tableaux Markdown.
8. Documentation, référence Alfred, validation.

## Suivi de complexité

| Écart | Pourquoi | Alternative plus simple rejetée |
|---|---|---|
| Six nouveaux fichiers | responsabilités distinctes, testables seules ; `TargetModeRuntimeController` (2 271 lignes) et `TargetOverlayPresenter` (3 570) ne doivent pas grossir de toute la logique | tout mettre dans ces deux fichiers : charge cognitive accrue |
| Panneau SF Symbols dédié | le modèle d'Alfred 6 a un aperçu à droite que la barre n'a pas | grille de la barre : perd l'aperçu et les versions |
