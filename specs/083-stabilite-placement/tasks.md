# Tâches 083

- [x] T1 Délai de placement des fenêtres neuves avant rattachement physique
  (`LayoutMaintainer.swift`, `LayoutTolerance.swift`) ; test
  `newWindowOpenedOnAnotherDisplayStaysOnTheFocusedDisplay`, en échec sans la correction.
- [x] T2 Refus de taille durable après une répétition identique (`ClampedFrame.lasting`,
  `expiredClamps`) ; test `identicalClampAfterExpiryBecomesLasting`, en échec sans la correction.
- [x] T3 Écriture annulée deux fois retenue sans délai (`RevertedAppliedFrame.reverts`) ; test
  `acceptedThenRevertedFrameIsNotRewrittenByEverySafetyPass` (12 écritures sans, au plus 3 avec).
- [x] T4 Membres retirés marqués fermés (`closeRetiredMembers`,
  `WindowSwitcherService.retiredWindows(pids:)`) ; `Spec083RetiredMembersTests`.
- [x] T5 Suite complète, installation, contrôle réel, intégration.
