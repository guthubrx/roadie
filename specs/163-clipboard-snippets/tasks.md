# Tasks 163 — Presse-papiers sécurisé & Snippets

- [ ] T1 : Config TOML, validation et catalogue de réglages (`ConfigClipboardSnippets.swift`, `Config.swift`, `ConfigLoaderAndValidation.swift`, `SettingsCatalog*.swift`, `SettingsOrganization.swift`, `SettingsCatalogTests.swift`)
- [ ] T2 : `ClipboardHistoryService.swift` (filtre sécurité strict, stockage atomique `0o600`, déduplication/épinglage/rétention, `ClipboardMonitor`)
- [ ] T3 : `SnippetsService.swift` (expansion mono-passe `{date}/{time}/{datetime}/{clipboard}/{cursor}`, recherche, `SnippetTypingBuffer`, `SnippetAutoExpander`)
- [ ] T4 : Intégration Lanceur (`TargetSearchSession.swift`, `LauncherSystemCommands.swift`), CLI (`CLICommandRouter.swift`) et cycle de vie daemon (`Sources/roadied/main.swift`)
- [ ] T5 : Tests complets (`Spec163ClipboardSnippetsTests.swift`), docs FR/EN, CHANGELOG, journal, suite complète + revue Bridget + livraison
