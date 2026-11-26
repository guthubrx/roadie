# Spec 171 — Tableau de bord Modules on/off, Onboarding 1er lancement & Consolidation

## Contexte & Problème
Roadie réunit désormais de nombreuses capacités optionnelles (saut dialogues Ouvrir/Enregistrer, repli OCR local Vision, profils matériels d’écrans, presse-papiers sécurisé `0o600`, snippets, auto-expansion, scratchpad, Dim Inactive, outils lanceur, gestes trackpad). Les utilisateurs doivent pouvoir **activer ou désactiver chaque module en un coup d’œil** au même endroit, savoir lesquels sont désactivés par défaut (coût zéro), et disposer d’un bilan d’accueil clair au premier lancement.

## Exigences fonctionnelles
- **FR-001 (Catalogue central des Modules)** : `RoadieModuleCatalog.all` référence chaque module activable/désactivable par son identifiant canonique `SettingDescriptor.id` (tous de type `.bool` dans `SettingsCatalog`), avec titre/description FR/EN, mention de charge au repos et statut par défaut.
- **FR-002 (Carte Modules dans Paramètres > Général)** : `SettingsModulesCard` affiche tous les interrupteurs directement dans `Paramètres > Général`, synchronisés en temps réel avec `SettingsViewModel`, avec accès direct à la catégorie de réglages avancés du module.
- **FR-003 (Checklist d’accueil 1er lancement)** : `OnboardingChecklist` résume l’état des prérequis (Accessibilité, Enregistrement d’écran, configuration active, raccourcis configurés, layout choisi) et est accessible en CLI (`roadie onboarding [--json]`) ainsi qu’en bloc compact dans `Paramètres > Général`.
