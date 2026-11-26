# Plan — Spec 168 : Saut direct dans les dialogues fichiers

1. **Configuration (`RoadieCore`)** :
   - Ajouter `fileDialogJump: Bool = true` (`file_dialog_jump`) dans `TargetModeConfig` (`Sources/RoadieCore/ConfigTargetMode.swift`).
   - Déclarer `"file_dialog_jump"` dans `ConfigValidationRules.knownKeys["experimental.target_mode"]` (`Sources/RoadieCore/ConfigLoaderAndValidation.swift`).
2. **Module isolé (`Sources/RoadieDaemon/FileDialogJumpService.swift`)** :
   - `FileDialogContext` (Sendable, Equatable) + `FileDialogKind` (`.open`, `.save`).
   - Détection pure testable `FileDialogJumpService.classify(role:subrole:identifier:title:hasFileBrowser:hasSaveField:)` + sonde AX bornée sur le PID au premier plan `detect(pid:appName:)`.
   - Résolution de cible `targetFolder(for path: String, isFolder: Bool) -> String?`.
   - Navigation `jump(to folder: String, in context: FileDialogContext)` via protocole injectable `FileDialogNavigating` (implémentation live macOS : réactivation app + `⌘⇧G` + écriture AX du champ `AXComboBox`/`AXTextField` + validation `Entrée`).
3. **Intégration lanceur** :
   - `LauncherVerb.useInFileDialog` dans `LauncherActions.swift` (`"Utiliser dans ce dialogue"` / `"Jump here in dialog"`).
   - `LauncherSearchContext.activeFileDialog: FileDialogContext?` + `fileDialogJumpEnabled: Bool`.
   - `TargetModeRuntimeController` : détection conditionnée à `barConfig.fileDialogJump`, suggestions de dossiers en tête de `idleRows`, exécution `.useInFileDialog` dans `performFile`.
   - `TargetSearchSession` : priorité `.useInFileDialog` pour `fileVerb` et `verbs(for:)` quand `activeFileDialog != nil`.
4. **Catalogue & tests** :
   - Descripteur dans `SettingsCatalog.swift`, mise à jour des compteurs dans `SettingsCatalogTests.swift`, suite TDD `Tests/RoadieDaemonTests/Spec168FileDialogJumpTests.swift`.
