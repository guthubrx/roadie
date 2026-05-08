# Implementation Plan: Roadie Ecosystem Upgrade

**Branch**: `002-roadie-ecosystem-upgrade` | **Worktree**: `.worktrees/002-roadie-ecosystem-upgrade/` | **Date**: 2026-05-08 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-roadie-ecosystem-upgrade/spec.md`

## Summary

Transformer Roadie d'un window manager local surtout piloté par raccourcis BTT en surface d'automatisation stable : catalogue d'événements observable, abonnement temps réel, état JSON contractuel, moteur de règles déclaratif, commandes power-user exposées, puis groupes de fenêtres. Le plan conserve les choix structurants déjà tranchés : pas de SIP off, pas d'API privée macOS en écriture, pas de Spaces natifs Apple, pas de hotkey daemon natif, pas de système de plugins runtime au premier passage.

La livraison doit être découpée en tranches compatibles avec le daily driver :

1. **Observation stable** : événements, abonnement, snapshots JSON, contrats CLI.
2. **Règles déclaratives** : matching fenêtre/contexte et actions sans scripting fragile.
3. **Commandes d'arbre** : primitives de layout exposées et testées.
4. **Groupes/stack** : conteneur visible permettant d'empiler plusieurs fenêtres dans un même slot.

## Technical Context

**Language/Version**: Swift 6.0 via Swift Package Manager  
**Primary Dependencies**: AppKit, Accessibility AX, TOMLKit, Swift ArgumentParser-like CLI maison, structures RoadieCore/RoadieDaemon/RoadieStages existantes  
**Storage**: fichiers JSON sous `~/.roadies/` (`events.jsonl`, `stages.json`, `layout-intents.json`) et configuration TOML Roadie existante  
**Testing**: `swift build`, `swift test`, Swift Testing dans `Tests/`, tests d'acceptation documentés par scénario SpecKit 002  
**Target Platform**: macOS 14+ desktop, daemon utilisateur `roadied`, CLI `roadie`  
**Project Type**: application desktop/daemon/CLI mono-utilisateur  
**Performance Goals**: publication d'un événement sans blocage visible du tiler, abonnement utilisable par une barre d'état, commandes CLI interactives en latence humaine (< 200 ms hors AX/macOS)  
**Constraints**: zéro API privée en écriture, zéro désactivation SIP, compatibilité avec les fichiers Roadie existants, aucun changement destructif de configuration, pas de daemon hotkey natif  
**Scale/Scope**: usage local avec plusieurs écrans, desktops virtuels, stages, dizaines de fenêtres, dizaines de règles, flux d'événements long vivant pendant toute la session utilisateur

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **SpecKit obligatoire** : spec 002 créée et branche `002-roadie-ecosystem-upgrade` active.
- **Worktree obligatoire** : implémentation à effectuer dans `.worktrees/002-roadie-ecosystem-upgrade/`, pas dans le checkout principal.
- **Décisions structurantes documentées** : ADR requis pour le contrat automation/event/rules, fourni dans `docs/decisions/001-roadie-automation-contract.md`.
- **Tests avant implémentation complète** : chaque tranche doit définir ses cas Swift Testing et au moins un scénario d'acceptation observable par CLI.
- **Gates Swift projet** : pour Roadie, les gates constitutionnelles TypeScript sont adaptées au stack Swift par `swift build` et `swift test`, complétés par validation manuelle CLI quand la tâche le demande.
- **Simplicité** : pas de serveur IPC séparé tant qu'un flux append-only + CLI follow répond au besoin ; extension socket possible plus tard si la latence ou le multiplexage l'exigent.
- **Observabilité** : chaque commande et règle appliquée doit pouvoir produire un événement corrélable.
- **Sécurité macOS** : aucune dépendance à OSAX, SkyLight privé, SIP off, injection globale de raccourcis ou plugin chargé dynamiquement.

**Post-Design Gate**: PASS sous réserve que la première implémentation respecte le découpage ci-dessus et ne mélange pas groupes/stack avec la fondation événementielle.

## Project Structure

### Documentation (this feature)

```text
specs/002-roadie-ecosystem-upgrade/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── cli.md
│   ├── config-rules.toml.md
│   └── events.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
Sources/
├── roadie/                 # CLI entrypoint and command routing
├── RoadieCore/             # Config model and shared domain types
├── RoadieDaemon/           # Event log, daemon state, stores, command handlers
└── RoadieStages/           # Runtime stage/desktop/display state model

Tests/
├── RoadieCoreTests/
├── RoadieDaemonTests/
└── RoadieStagesTests/
```

**Structure Decision**: conserver les frontières existantes. Les types contractuels partagés vont dans `RoadieCore`; la publication, persistance et exécution des règles restent côté `RoadieDaemon`; le CLI ne doit être qu'une façade de parsing/formatage.

## Phase 0: Research

Voir [research.md](./research.md).

Décisions clés :

- Flux événementiel basé sur un contrat JSON versionné, rétrocompatible avec `events.jsonl`.
- Abonnement CLI par suivi du journal append-only en première tranche, avec snapshot initial optionnel.
- Règles en TOML déclaratif, évaluées par priorité stable et compilées en matchers validables.
- Groupes modélisés comme conteneurs Roadie internes, pas comme Spaces macOS ni tabs système.

## Phase 1: Design

Voir :

- [data-model.md](./data-model.md)
- [contracts/events.md](./contracts/events.md)
- [contracts/cli.md](./contracts/cli.md)
- [contracts/config-rules.toml.md](./contracts/config-rules.toml.md)
- [quickstart.md](./quickstart.md)
- [ADR automation contract](../../docs/decisions/001-roadie-automation-contract.md)

## Phase 2: Task Planning Approach

La génération de tâches doit séparer strictement les lots suivants :

1. **Fondation events/state** : types, journal, abonnement, commandes de lecture, tests de compatibilité.
2. **Rules engine** : parsing TOML, validation, matching, actions, événements de rule hit/skip.
3. **Tree commands** : exposition CLI des primitives existantes ou ajout de primitives minimales.
4. **Groups** : modèle, persistance, rendu layout, commandes, événements.
5. **Hardening** : migration de fichiers existants, documentation utilisateur, tests d'acceptation multi-display simulés, matrice de couverture des cas yabai/AeroSpace/Hyprland.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Contrats JSON versionnés | Les intégrations externes ont besoin d'une surface stable | Le JSON ad hoc actuel casse dès qu'une clé change |
| ADR dédié | Le choix event/rules fixe l'écosystème Roadie | Une note dans le plan serait trop facile à perdre |
| Règles compilées avant exécution | Éviter les effets partiels et erreurs silencieuses | Matcher directement à chaque fenêtre rend les diagnostics faibles |
| Adaptation des gates de test | Le projet est Swift, pas TypeScript/Next.js | Appliquer `pnpm` serait inopérant et masquerait la vraie validation |

## Progress Tracking

**Phase Status**:

- [x] Phase 0: Research complete
- [x] Phase 1: Design complete
- [x] Phase 2: Task planning approach defined
- [x] Phase 3: Tasks generated
- [ ] Phase 4: Implementation
- [ ] Phase 5: Validation

**Gate Status**:

- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented
