# ADR 001: Roadie Automation Contract

**Status**: Proposed  
**Date**: 2026-05-08  
**Feature**: `002-roadie-ecosystem-upgrade`

## Context

Roadie dispose déjà d'un CLI, d'un journal d'événements JSONL, d'un état persistant pour les stages/desktops et d'un modèle de configuration TOML. En revanche, ces surfaces sont surtout utiles au debug interne. Elles ne forment pas encore un contrat stable pour des intégrations externes comme une barre d'état, des scripts utilisateur, BetterTouchTool, ou des dashboards.

Les comparaisons avec yabai, AeroSpace et Hyprland montrent que l'écosystème se construit d'abord sur trois primitives : événements publiés, état interrogeable, règles déclaratives.

## Decision

Roadie adopte un contrat d'automatisation progressif :

1. événements JSON Lines versionnés, persistés dans `~/.roadies/events.jsonl`.
2. abonnement CLI `roadie events subscribe` en première tranche.
3. commandes de lecture `roadie query ...` avec schémas stables.
4. moteur de règles TOML compilé et validable avant exécution.
5. groupes de fenêtres modélisés dans Roadie, sans API macOS privée.

Roadie ne crée pas de hotkey daemon natif, ne pilote pas les Spaces Apple, ne désactive pas SIP, et ne charge pas de plugins dynamiques dans cette feature.

## Consequences

**Positive**:

- Les intégrations externes obtiennent une surface stable.
- Les logs deviennent exploitables en production locale.
- Les futures commandes socket peuvent réutiliser le même contrat.
- Les règles sont versionnables et diagnostiquables.

**Negative**:

- Le premier abonnement via journal append-only est moins riche qu'un vrai socket bidirectionnel.
- Les payloads versionnés imposent une discipline de compatibilité.
- Les règles TOML demandent un validateur sérieux avant application.

## Validation

- Tests Swift sur sérialisation/désérialisation des événements.
- Tests de compatibilité sur ajout de champs inconnus.
- Tests de validation TOML rules.
- Tests CLI sur `subscribe`, `query`, `rules validate`.
- Scénarios d'acceptation documentés dans `specs/002-roadie-ecosystem-upgrade/quickstart.md`.
