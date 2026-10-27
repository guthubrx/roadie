# Tâches 094

- [x] T001 `LauncherWeb.searchText` (`LauncherSearchContext.swift`) : `^` en tête retiré ; lignes Web et
  ⌃ Retour (`LauncherActions.swift`) l'utilisent ; `LauncherList.prependSection` place la section Web en
  tête pour `^texte` (`TargetOverlayPresenter.swift`). (FR-001)
- [x] T002 `followBrowser` (`TargetModeRuntimeController.swift`) après `performURL` (ouvrir) et ⌃ Retour ;
  journal `launcher.follow_browser`. (FR-002)
- [x] T003 `AlfredGridView.learnsOrder` et `learned` ; appliqué par `refreshGrid`. (FR-003)
- [x] T004 Tests `Tests/RoadieDaemonTests/Spec094WebGridTests.swift` ; suite complète ; installation.

Analyse : couverture 3/3 ; recherche d'existant : `LauncherList.prepend` (une ligne) étendu en
`prependSection`, `launch(_:)`/`preferredWindow` réutilisés, classement `LauncherRanking` réutilisé
(`frecency`, `exactUses`). Converge : CONVERGED (FR-001 à FR-003 reliés au code et aux tests ; FR-002
sans test automatique, essai utilisateur).
