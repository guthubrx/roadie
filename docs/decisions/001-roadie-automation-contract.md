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

## Suivi Spec 002

La spec 002 est exécutée dans le worktree dédié `.worktrees/002-roadie-ecosystem-upgrade/`.

Gates obligatoires pour les tâches de code :

1. `swift build`
2. `swift test` ou filtre Swift Testing ciblé
3. validation CLI manuelle quand la tâche touche `roadie`
4. journalisation dans `specs/002-roadie-ecosystem-upgrade/implementation.md`
5. commit dédié par tâche validée

Décisions à surveiller pendant l'implémentation :

- si `events subscribe` par suivi JSONL ne respecte pas la latence SC-001, rouvrir l'ADR pour évaluer un socket dédié.
- si `scratchpad` ne peut pas être appliqué sans workflow complet, conserver au minimum le marqueur contractuel dans les règles et queries.
- si l'indicateur visuel des groupes surcharge les bordures existantes, limiter la première version à l'état JSON + variation de border stable.
