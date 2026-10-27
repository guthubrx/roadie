# Validation 097

- Build `./scripts/with-xcode swift build` réussi.
- Suite complète : 2 121 tests / 298 suites ; un échec de délai sous charge
  (`Audit022LotITests.daemonListeningOnSocketIsUsedEvenWithoutPidFile`), connu en 096 et réussi seul.
- Tests ajoutés : `Tests/RoadieDaemonTests/Spec097PreviousWindowTests.swift` (2 tests).
- Focus après Échap : non vérifiable par test (Accessibilité d'une autre application). Essai réel à faire
  dans T3 Code, à lire dans l'événement `launcher.focus_restore`.
