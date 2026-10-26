# Tâches 090

## US1 Web (P1)
- [x] T001 Tests puis reconnaissance d'adresse, recherches par mot-clé et lignes de repli
  (`LauncherWeb`) (`Tests/RoadieDaemonTests/Spec090WebTests.swift`). FR-001 à FR-003.
- [x] T002 Réglages `web_searches` (tableau de tables) et `fallback_searches` (`Config.swift`). FR-003.
- [x] T003 Liste et barre : adresse et mot-clé en tête, section Web à la fin (avec les replis de
  la 089), choix par défaut (`LauncherList.swift`, `TargetOverlayPresenter.swift`). FR-001 à FR-003.
- [x] T004 `LauncherSubject.url` et ses verbes ; ouverture dans une nouvelle fenêtre placée (R2)
  (`LauncherActions.swift`, `TargetModeRuntimeController.swift`). FR-002.

## US2 Historique (P2)
- [x] T005 Tests puis `LauncherHistoryStore` ; reprise sous 5 minutes sélectionnée ; recherches
  récentes dans la barre vide ; `roadie launcher history [--clear]`
  (`Tests/RoadieDaemonTests/Spec090HistoryTests.swift`). FR-004, FR-005.

## Livraison
- [x] T006 Suite complète, installation, santé ; docs FR/EN, CHANGELOG, index, `validation.md`.

## Convergence
- [x] T007 `yt` seul (mot-clé exact sans espace) propose l'invite, sans prendre la sélection (FR-003).
