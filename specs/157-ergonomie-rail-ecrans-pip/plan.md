# Plan d'implémentation — Spec 157

## Architecture retenue

### 1. Réglages (respect strict de `docs/dev/ajouter-un-reglage.md`)
- `Sources/RoadieCore/Config.swift` :
  - `TilingConfig.floatPictureInPicture: Bool = true` (`float_picture_in_picture` dans `CodingKeys`, `init(from:)`, `ConfigValidationRules.knownKeys["tiling"]`).
  - `ConfigValidationRules.knownKeys["fx.rail"]` : ajout de `"show_app_icons_row"` (les réglages du rail sont lus dans `RailSettings.swift`).
- `Sources/RoadieDaemon/RailSettings.swift` + `RailVisualConfig.swift` :
  - `RailSettings.showAppIconsRow: Bool = true`, lu depuis `[fx.rail] show_app_icons_row` (défaut `true`), propagé dans `RailVisualConfig.showAppIconsRow`.
- `Sources/RoadieDaemon/SettingsCatalog.swift` + `SettingsCatalogRail.swift` :
  - Descripteurs FR/EN pour `tiling.float_picture_in_picture` (catégorie `.tuilage`) et `fx.rail.show_app_icons_row` (catégorie `.rail`).
- `Tests/RoadieDaemonTests/SettingsCatalogTests.swift` : mise à jour des compteurs (`simple`: 313 → 315, `railSimple`: 80 → 81, hors rail: 233 → 234).
- `docs/fr/features.md`, `docs/en/features.md`, `CHANGELOG.md` : documentation des nouveautés et réglages.

### 2. US1 — NavRail : rangée d'icônes d'applications sous chaque carte
- `Sources/RoadieDaemon/StageCardView.swift` :
  - Helper pur `static func distinctAppBundleIDs(for members: [PersistentStageMember], maxCount: Int = 6) -> (bundleIDs: [String], overflow: Int)` (O(m), ordre d'apparition préservé).
  - Helper pur `appIconsRowFrames(in:preview:)` qui place une rangée centrée d'icônes (16 pt, espacement 4 pt) juste sous l'aperçu (et au-dessus de la légende quand `placement == .below`), sans modifier `drawFullIndicator` ni `drawCornerIndicator`.
  - Réserve de hauteur dédiée uniquement quand `config.showAppIconsRow && config.mode != .icons && !visualMembers.isEmpty` afin de préserver la géométrie des cartes vides et du mode `icons-only`.
  - En cas de `slotHeight > 0` serré, la hauteur de l'aperçu s'adapte proprement comme elle le fait déjà pour la légende.

### 3. US2, US3, US4 — Actions rapides (`balance`, `display swap`, `stage prune-empty`)
- `Sources/RoadieDaemon/DisplayCommands.swift` :
  - `DisplayCommandService.swap(target: StageDisplayMoveTarget? = nil) -> StageCommandResult` :
    - Résout l'écran actif et l'écran cible (direction, index ou autre écran par défaut si `target == nil` et >= 2 écrans).
    - Transaction atomique `service.commitStageTransfer` : échange les deux stages actifs entre `scopeA` et `scopeB` (en évitant les collisions d'ID, en conservant noms personnalisés, modes, `bspTree`, `groups`, `focusedWindowID`, `previousFocusedWindowID`, en mettant à jour les `windowPins` homeScope, et en effaçant les intents des deux scopes).
    - Applique le placement des fenêtres des deux stages échangés en un seul `CommandPlacement` (`restoring` centré sur le nouvel écran + relayout des deux scopes).
- `Sources/RoadieDaemon/StageCommands.swift` :
  - `StageCommandService.pruneEmpty(displayID: DisplayID? = nil) -> StageCommandResult` :
    - Transaction `store.mutateChecked` : retire les stages où `Self.isPrunableEmpty(stage, activeStageID:liveWindowIDs:now:)` est vrai (`isDeletable` ET `!StagePresentationOrder.isNamed(stage)`).
- `Sources/RoadieDaemon/CLICommandRouter.swift` :
  - `display swap [N|left|right|up|down]` et `stage prune-empty` (usage + routage).
- `Sources/RoadieDaemon/RailController.swift` :
  - Ajout de `RailAction.balanceLayout`, `RailAction.swapDisplay(DisplayID)`, `RailAction.pruneEmptyStages` dans le menu contextuel du rail et `perform(_:displayID:)`.
- `Sources/RoadieDaemon/LauncherSystemCommands.swift` :
  - Ajout de 3 commandes système Roadie (`roadie-balance`, `roadie-display-swap`, `roadie-prune-empty`) exécutées directement via le `SnapshotService` / `LayoutCommandService` / `DisplayCommandService` / `StageCommandService` (ou via le CLI/notification interne sans sous-processus lourd).

### 4. US5 — Picture-in-Picture flottant automatiquement
- `Sources/RoadieDaemon/DaemonSnapshot.swift` :
  - Helper pur `static func isPictureInPictureWindow(_ window: WindowSnapshot) -> Bool` appelé dans `baseTilingDecision` quand `config.tiling.floatPictureInPicture` est actif (avant l'étape 5 des règles utilisateur, permettant un override explicite `action.manage = true`).

## Risques et garde-fous
- Ne pas casser les tests de géométrie existants du rail (`Spec032RailGeometryTests`, `Spec033CaptionTests`, `RailTypographyTests`).
- Après ajout d'un champ à `TilingConfig` (`RoadieCore`), penser au piège connu de `AGENTS.md` (nettoyer `RoadieTilerTests.build` si signal 11).
- Garantir la non-suppression des stages nommées, actives, parquées ou occupées dans `pruneEmpty`.
