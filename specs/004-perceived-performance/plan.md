# Plan d'Implémentation : Performance ressentie Roadie

**Branche**: `027-perceived-performance` | **Date**: 2026-05-09 | **Spécification**: [spec.md](./spec.md)  
**Entrée**: Spécification fonctionnelle depuis `specs/004-perceived-performance/spec.md`

## Résumé

Améliorer la fluidité perçue de Roadie en traitant d'abord le problème comme un sujet d'observabilité utilisateur : mesurer les interactions critiques, identifier les étapes lentes, puis optimiser progressivement les chemins stage, desktop, AltTab, rail et corrections de layout. L'approche conserve les garanties récentes de stabilité : les lectures restent sans effet de bord, les commandes explicites partent de l'état Roadie, et la boucle périodique reste un filet de sécurité plutôt que le chemin principal.

## Contexte Technique

**Langage/Version**: Swift 6.0  
**Dépendances principales**: AppKit, Foundation, ApplicationServices/Accessibility, Swift Testing, TOMLKit existant  
**Stockage**: Fichiers locaux existants sous `~/.roadies/` et `~/.local/state/roadies/`; nouvel historique court de performance dans `~/.local/state/roadies/performance.json`, borné à 100 interactions avec rotation FIFO
**Tests**: Swift Testing via `make test`; validation build via `make build`; validation runtime via `./bin/roadie daemon health` après relance  
**Plateforme cible**: macOS 14+  
**Type de projet**: Swift Package avec bibliothèques, daemon, CLI et surfaces AppKit auxiliaires  
**Objectifs performance**: Stage direct p95 < 150 ms; desktop p95 < 200 ms; AltTab vers fenêtre gérée p90 < 250 ms; surcoût rail/diagnostic < 10% de médiane  
**Contraintes**: Pas d'APIs privées macOS; pas d'animations système; pas de Control Center dans le chemin critique; ne pas réintroduire de lectures mutatrices; préserver restore safety et transient windows; tolérance initiale des frames équivalentes fixée à 2 points macOS
**Échelle/Périmètre**: Optimisation monoposte sur un environnement macOS avec plusieurs écrans, desktops virtuels Roadie, stages, rail optionnel et dizaines de fenêtres gérées

## Vérification Constitution

*GATE : doit passer avant la recherche Phase 0. Re-vérifier après le design Phase 1.*

- **Langue française**: PASS. Les artefacts SpecKit sont rédigés en français.
- **Processus SpecKit complet**: PASS. La feature suit spec → plan → tasks → implémentation.
- **Diagnostic avant modification**: PASS. La première tranche impose l'instrumentation avant l'optimisation.
- **ADR pour décision structurante**: PASS. Un ADR est prévu si le plan introduit une nouvelle politique de chemin critique ou d'observabilité performance durable.
- **Tests avant validation**: PASS. Les critères demandent tests de régression stage, desktop, AltTab, rail et lecture sans effet de bord.
- **Anti scope-creep**: PASS. Animations, APIs privées et refonte Control Center sont explicitement hors périmètre.
- **Sécurité opérationnelle**: PASS. La boucle périodique, restore safety et transient windows restent des protections, pas des optimisations supprimées.

## Structure Projet

### Documentation (cette fonctionnalité)

```text
specs/004-perceived-performance/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── cli.md
│   ├── events.md
│   └── state.md
└── tasks.md
```

### Code Source (racine du dépôt)

```text
Sources/
├── RoadieCore/
│   ├── AutomationEvent.swift
│   ├── AutomationSnapshot.swift
│   └── Config.swift
├── RoadieDaemon/
│   ├── AutomationQueryService.swift
│   ├── DaemonSnapshot.swift
│   ├── DesktopCommands.swift
│   ├── DisplayCommands.swift
│   ├── EventLog.swift
│   ├── EventSubscriptionService.swift
│   ├── FocusStageActivationObserver.swift
│   ├── LayoutMaintainer.swift
│   ├── Metrics.swift
│   ├── PerformanceRecorder.swift
│   ├── PerformanceStore.swift
│   ├── RailController.swift
│   ├── StageCommands.swift
│   ├── StageStore.swift
│   ├── TransientWindowDetector.swift
│   └── WindowCommands.swift
├── roadie/
│   └── main.swift
└── roadied/
    └── main.swift

Tests/
├── RoadieDaemonTests/
│   ├── EventCatalogTests.swift
│   ├── LayoutMaintainerTests.swift
│   ├── PowerUserDesktopCommandTests.swift
│   ├── PowerUserFocusCommandTests.swift
│   ├── QueryCommandTests.swift
│   └── SnapshotServiceTests.swift
└── RoadieStagesTests/
    └── RoadieStateTests.swift
```

**Décision de structure**: Garder la fonctionnalité dans les targets existants. Les modèles de mesure et contrats exposés appartiennent à `RoadieCore` quand ils sont sérialisés ou visibles via query/events. L'orchestration et les mesures runtime restent dans `RoadieDaemon`. La CLI expose uniquement la consultation et les commandes de diagnostic. Aucun nouveau target n'est nécessaire pour cette session.

## Suivi de Complexité

| Écart | Pourquoi nécessaire | Alternative plus simple rejetée car |
|-------|---------------------|-------------------------------------|
| Aucun écart constitutionnel identifié | N/A | N/A |

## Phase 0 : Recherche

Voir [research.md](./research.md). Décisions principales :

- Mesurer avant d'optimiser, avec une trace légère par interaction critique.
- Découper les mesures en étapes utilisateur : capture état, changement contexte, masquage/restauration, layout, focus, travail secondaire.
- Conserver les lectures read-only comme règle stricte pour query/metrics/diagnostics.
- Optimiser stage/desktop/AltTab par chemins directs et scope limité avant de toucher à la boucle globale.
- Garder le rail et les métriques hors du chemin critique ; ils peuvent se rafraîchir après l'action.
- Conserver le timer périodique comme filet de sécurité et déplacer progressivement les actions utilisateur vers des déclenchements événementiels.

## Phase 1 : Conception & Contrats

Voir :

- [data-model.md](./data-model.md)
- [contracts/cli.md](./contracts/cli.md)
- [contracts/events.md](./contracts/events.md)
- [contracts/state.md](./contracts/state.md)
- [quickstart.md](./quickstart.md)

## Vérification Constitution (Après conception)

- **Langue française**: PASS.
- **Diagnostic avant modification**: PASS, les premières tâches devront produire métriques et baseline.
- **Tests**: PASS, les contrats définissent des sorties vérifiables et les scénarios ciblent les régressions observées.
- **Scope**: PASS, pas d'animations, pas d'APIs privées, pas de refonte UI.
- **Sécurité opérationnelle**: PASS, les protections existantes restent actives et les optimisations se limitent au chemin critique utilisateur.
