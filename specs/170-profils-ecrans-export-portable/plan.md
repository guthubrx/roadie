# Plan — Spec 170 : Profils d’écrans & Export/Import portable

1. **Configuration (`RoadieCore`)** :
   - Ajouter `displayProfilesEnabled: Bool = false` (`display_profiles_enabled`) dans `TilingConfig` (`Sources/RoadieCore/Config.swift`).
   - Ajouter `"display_profiles_enabled"` dans `ConfigValidationRules.knownKeys["tiling"]` (`Sources/RoadieCore/ConfigLoaderAndValidation.swift`).
   - Ajouter le descripteur dans `SettingsCatalog.swift`.
2. **Module `Sources/RoadieDaemon/DisplayProfileService.swift`** :
   - `DisplayTopologySignature`, `DisplayProfile`, `DisplayProfileBook`, `DisplayProfileStore` (persistance atomique JSON dans `~/.roadies/display-profiles.json`).
   - `DisplayProfileService` (`saveCurrent`, `match`, `shouldAutoApply`, `list`, `delete`).
3. **Module `Sources/RoadieDaemon/PortableConfigService.swift`** :
   - `PortableConfigBundle` (`schemaVersion`, `exportedAt`, `roadieVersion`, `configToml`, `projects`, `aliases`, `displayProfiles`).
   - `PortableConfigService.exportBundle(...)` et `importBundle(..., dryRun:force:)` avec validation TOML préalable et backup automatique.
4. **CLI (`CLICommandRouter.swift`)** :
   - `roadie config export [PATH] [--json]` et `roadie config import <PATH> [--dry-run] [--force] [--json]`.
   - `roadie profile list|save|apply|delete [--json]`.
5. **Tests TDD (`Tests/RoadieDaemonTests/Spec170DisplayProfilesPortableConfigTests.swift`)**.
