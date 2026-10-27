# Validation 096

- Build : `./scripts/with-xcode swift build` réussi, après rebase sur la session 095.
- Suite complète : 2 119 tests / 297 suites. Un échec de délai sous charge
  (`Audit022LotITests.daemonListeningOnSocketIsUsedEvenWithoutPidFile`, réponse au-delà de 5 s),
  réussi relancé seul (18 tests). Avant le rebase, `Spec088ScriptRunnerTests.cancelStopsTheWholeProcessGroup`
  avait aussi dépassé son délai (5,05 s pour 5 s), puis réussi seul. Fichiers non touchés par la session.
- Tests ajoutés : `Tests/RoadieDaemonTests/Spec096IdleSettingsTests.swift` (3 tests).
- Comptes du catalogue mis à jour : 207 réglages simples, 34 plages hors rail.
