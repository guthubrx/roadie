# Plan — Spec 171 : Modules on/off & Onboarding

1. Créer `Sources/RoadieDaemon/RoadieModulesCatalog.swift` (`RoadieModuleDescriptor`, `RoadieModuleCatalog`, `OnboardingChecklist`, `SettingsModulesCard`).
2. Intégrer `SettingsModulesCard` dans `SettingsView.swift` (onglet `Général`) et `roadie onboarding [--json]` dans `CLICommandRouter.swift`.
3. Ajouter `Tests/RoadieDaemonTests/Spec171ModulesOnboardingTests.swift` vérifiant l’intégrité 100 % des liens `RoadieModuleCatalog` → `SettingsCatalog` (tous existants et `.bool`) et la logique `OnboardingChecklist`.
4. Exécuter la suite complète (`Spec168`, `Spec169` avec benchmark OCR réel, `Spec170`, `Spec171`, `SettingsCatalogTests`, `Spec155ConfigGuardTests`, puis suite globale) et documenter en FR/EN.
