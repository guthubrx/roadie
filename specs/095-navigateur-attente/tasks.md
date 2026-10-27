# Tâches 095

- [x] T001 Trace et second essai de `followBrowser` (`TargetModeRuntimeController.swift`). (FR-001)
- [x] T002 `AlfredLiveEffects.openURL`/`webSearch` appellent `follow` pour http/https ; câblé aux deux
  créations des effets réels. (FR-002)
- [x] T003 `AlfredGridView.loadingText`/`isWaiting` ; moteur : vue d'attente puis tuiles ou échec ;
  barre : ligne d'attente, `updateGrid` ; contrôleur : `openGrid` reçoit les tuiles. (FR-003)
- [x] T004 Tests (`Spec095GridLoadingTests`, `Spec092GridTests` adapté) ; suite complète ; installation.

Analyse : couverture 3/3. Existant réutilisé : `followBrowser` (094), `presentGrid`, `refreshGrid`.
Converge : CONVERGED (FR-001 et FR-002 sans test automatique : effets réels, à vérifier au journal).
