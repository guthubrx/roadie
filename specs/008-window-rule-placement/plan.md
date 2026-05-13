# Implementation Plan: Placement des fenetres par regle

**Branch**: `008-window-rule-placement` | **Date**: 2026-05-13 | **Spec**: `specs/008-window-rule-placement/spec.md`
**Input**: demande utilisateur : permettre qu'une application s'ouvre toujours sur une stage particuliere et sur un ecran particulier.

## Summary

Etendre le moteur `[[rules]]` existant pour appliquer un placement automatique par application : stage cible, display cible et option explicite de suivi du focus (`follow`). L'approche conserve le matcher et le validateur actuels, ajoute les champs manquants au modele, puis applique le placement dans `LayoutMaintainer` de facon idempotente avant le relayout courant.

## Technical Context

**Language/Version**: Swift 6 / SwiftPM  
**Primary Dependencies**: AppKit, Accessibility AX, TOMLKit, modules internes RoadieCore/RoadieDaemon/RoadieAX/RoadieStages  
**Storage**: fichiers JSON Roadie existants (`StageStore`, layout intents), configuration TOML existante  
**Testing**: Swift Testing via `./scripts/with-xcode swift test`  
**Target Platform**: macOS daemon + CLI Roadie  
**Project Type**: application desktop macOS / daemon de gestion de fenetres  
**Performance Goals**: placement en un tick maintainer, sans boucle de relayout, sans scan AX additionnel lourd  
**Constraints**: pas de dependance SkyLight/OSAX, pas de vol de focus par defaut, fail-safe si display absent  
**Scale/Scope**: nombre de fenetres/stages local et borne, multi-display utilisateur

## Constitution Check

- Specification avant implementation : OK.
- User stories testables independamment : OK.
- Pas de changement destructif de state : OK, placement idempotent et report si cible absente.
- Pas d'IA/anonymat Git : a respecter au commit.
- Tests automatises requis : parsing, validation, placement stage, placement display, display absent, follow.

Re-check apres design : OK, pas de violation justifiant une complexite additionnelle.

## Project Structure

### Documentation

```text
specs/008-window-rule-placement/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── toml-rules.md
└── tasks.md
```

### Source Code

```text
Sources/
├── RoadieCore/
│   ├── WindowRule.swift
│   └── AutomationEventCatalog.swift
└── RoadieDaemon/
    ├── WindowRuleEngine.swift
    ├── WindowRuleValidator.swift
    ├── LayoutMaintainer.swift
    └── Formatters.swift

Tests/
└── RoadieDaemonTests/
    ├── Fixtures/Spec002Rules.toml
    ├── WindowRuleConfigTests.swift
    ├── WindowRuleValidationTests.swift
    └── WindowRuleMaintainerTests.swift
```

**Structure Decision**: feature transversale minimale dans le systeme de regles existant. Aucun nouveau module ; le placement est une action de regle, appliquee par le maintainer.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Aucune | N/A | N/A |
