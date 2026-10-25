# Validation - Session 065

## Diagnostic

- Événements : `switcher.activate` et `overview.activation_failed` sur la fenêtre 781,
  message `switcher activate: restore failed`.
- Inventaire CoreGraphics : 781 « AlDente », couche 0, hors écran, pid 61329 vivant.
- SkyLight (`SLSCopySpacesForWindows`, masque 7) : aucun bureau pour 781 ; bureau 3 pour
  les fenêtres visibles. Seul membre de stage persisté dans ce cas : 781.

## Tests

- Ciblés : 139 tests / 23 suites (Spec036, 037, 056, 060, 065) réussis.
- Suite complète par `scripts/test --no-parallel` : 1 934 tests / 241 suites réussis.
- Défaut préexistant corrigé : `stageAssignEmptySkipsNamedEmptyStagesAndCreatesNextStage`
  lisait la configuration réelle (`expandingTildeInPath` ignore `HOME`). Il échouait aussi
  sur `main` depuis la suppression des workspaces de la configuration utilisateur, le
  2026-10-25 à 04:56. Stage 3 nommée dans le test et configuration explicite.
- Le compilateur Swift 6.2.3 du dossier Toolchains plante sur `RoadieTiler` en debug :
  utiliser `scripts/with-xcode` ou `scripts/test`.

## Installation

- `make install` puis `make restart` : PID 62987, signature `roadied-cert` conservée.
- `roadie query health` : 5/5 (process, daemon-status, self-test, state-audit,
  macos-window-settings).
- Configuration utilisateur inchangée par l'installation (sauvegarde
  `roadies.toml.bak-20261025-avant065`).

## Contrôle réel

`roadie switcher show` : 5 fenêtres listées, AlDente absente ; panneau fermé par
`roadie switcher cancel`.

Preuves : diaporama non produit. La capture montrait des contenus privés (session 064) ;
elle a été examinée localement puis supprimée.
