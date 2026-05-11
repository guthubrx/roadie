# Implémentation : Pins de Fenêtres

## Résultat

Implémenté.

## Validation automatisée

- `desktop` pin : couvert par `WindowPinSnapshotTests.desktopPinKeepsHomeScopeButLeavesActiveLayout`.
- `all_desktops` pin : couvert par `WindowPinSnapshotTests.pinVisibilityIsLimitedByScope`.
- restauration d'un pin caché : couvert par `WindowPinLayoutMaintainerTests.visiblePinHiddenInCornerIsRestoredToLastFrame`.
- non-masquage d'un pin visible : couvert par `WindowPinLayoutMaintainerTests.inactiveDesktopPinIsNotHiddenWhenDesktopIsActive`.
- retrait du pin : couvert par `TitlebarContextMenuTests.pinnedActionCanChangeScopeAndUnpin`.
- nettoyage automatique : couvert par `WindowPinSnapshotTests.snapshotPrunesMissingWindowPinsAndLogsEvent`.
- cohérence après déplacement stage/desktop/display : couverte par `TitlebarContextMenuTests.movingPinnedWindowToAnotherStageUpdatesPinHomeScope`, `PowerUserDesktopCommandTests.desktopAssignUpdatesPinnedWindowHomeScope`, `StageDisplayMoveTests.stageDisplayMoveUpdatesPinnedWindowHomeDisplay`.

## Validation globale

- `make test` : 274 tests passés.
- `make build` : compilation passée.

## Notes manuelles

Les scénarios du quickstart restent à valider dans une session graphique réelle après déploiement du binaire : pin desktop avec changements répétés de stage/desktop, pin all desktops avec changements répétés, puis unpin.
