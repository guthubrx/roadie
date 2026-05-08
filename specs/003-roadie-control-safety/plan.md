# Plan d'Implémentation : Roadie Control & Safety

**Branche**: `003-roadie-control-safety` | **Date**: 2026-05-08 | **Spécification**: [spec.md](./spec.md)  
**Entrée**: Spécification fonctionnelle depuis `specs/003-roadie-control-safety/spec.md`

## Résumé

Livrer une couche macOS de controle et de securite autour de Roadie : menu bar + settings, reload de configuration atomique, restauration en cas d'arret/crash, pause sur fenetres systeme transitoires, persistance layout v2 par identite stable, puis commandes width presets/nudge. L'approche reprend les idees robustes observees dans Miri tout en excluant animations, SkyLight prive et MultitouchSupport.

## Contexte Technique

**Langage/Version**: Swift 6.0  
**Dépendances principales**: AppKit, SwiftUI, ApplicationServices/Accessibility, Foundation, TOMLKit existant  
**Stockage**: Fichiers locaux existants (`~/.config/roadies/roadies.toml`, `~/.roadies/events.jsonl`, `~/.local/state/roadies/*`)  
**Tests**: Swift Testing via `make test`; validation build via `make build`  
**Plateforme cible**: macOS 14+  
**Type de projet**: Swift Package avec app desktop, daemon et CLI  
**Objectifs performance**: Reload config et status menu perceptibles en moins de 500 ms hors build; watcher crash restaure en moins de 2 s en test  
**Contraintes**: Pas d'animations dans cette session; pas de dependance SkyLight/MultitouchSupport; pas de daemon hotkey natif complet; ne pas casser BTT/CLI  
**Échelle/Périmètre**: Environ 6 increments fonctionnels, tous verifies par tests unitaires et commandes/query/events quand possible

## Vérification Constitution

*GATE : doit passer avant la recherche Phase 0. Re-verifier apres le design Phase 1.*

- **Langue francaise**: PASS. Les artefacts SpecKit sont rediges en francais.
- **Processus SpecKit complet**: PASS. Spec, plan, tasks et analyse sont produits avant implementation.
- **ADR obligatoire pour decision structurante**: PASS avec tache dediee pour documenter la politique "public APIs only / no animations".
- **Tests avant validation**: PASS. Les taches incluent tests Swift par increment et validation `make build`/`make test`.
- **Anti scope-creep**: PASS. Les animations et hotkey daemon complet sont explicitement hors scope.
- **Securite operationnelle**: PASS. Le plan priorise rollback config, restore safety et transient windows avant confort UX.

## Structure Projet

### Documentation (cette fonctionnalité)

```text
specs/003-roadie-control-safety/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── cli.md
│   ├── config.md
│   ├── events.md
│   └── ui.md
└── tasks.md
```

### Code Source (racine du dépôt)

```text
Sources/
├── RoadieCore/
│   ├── Config.swift
│   ├── AutomationEvent.swift
│   └── AutomationSnapshot.swift
├── RoadieAX/
│   └── SystemSnapshotProvider.swift
├── RoadieDaemon/
│   ├── AutomationQueryService.swift
│   ├── AutomationSnapshotService.swift
│   ├── ConfigReloadService.swift
│   ├── ControlCenterState.swift
│   ├── RestoreSafetyService.swift
│   ├── TransientWindowDetector.swift
│   ├── WindowIdentity.swift
│   ├── WidthAdjustmentService.swift
│   ├── LayoutMaintainer.swift
│   ├── LayoutIntentStore.swift
│   ├── RailController.swift
│   └── EventLog.swift
├── RoadieControlCenter/
│   ├── ControlCenterApp.swift
│   ├── ControlCenterMenu.swift
│   └── SettingsWindow.swift
├── roadie/
│   └── main.swift
└── roadied/
    └── main.swift

Tests/
├── RoadieDaemonTests/
│   ├── ConfigReloadTests.swift
│   ├── ControlCenterStateTests.swift
│   ├── RestoreSafetyTests.swift
│   ├── TransientWindowDetectorTests.swift
│   ├── WindowIdentityTests.swift
│   └── WidthAdjustmentTests.swift
└── RoadieControlCenterTests/
    └── ControlCenterStateRenderingTests.swift

docs/decisions/
└── 002-control-safety-public-api-boundary.md
```

**Décision de structure**: Ajouter un target Swift dedie `RoadieControlCenter`. Le code AppKit/SwiftUI reste isole du daemon pour eviter de coupler `roadied` a l'UI et pour tester les modeles de rendu sans lancer le daemon. Les services non visuels restent dans `RoadieDaemon`; les modeles partages et contrats JSON restent dans `RoadieCore`.

## Suivi de Complexité

| Écart | Pourquoi nécessaire | Alternative plus simple rejetée car |
|-----------|------------|-------------------------------------|
| Nouveau target Swift `RoadieControlCenter` | Isoler AppKit/SwiftUI du daemon et tester les modeles UI sans lancer `roadied` | Tout mettre dans `RoadieDaemon` rendrait le daemon plus couple a l'UI et compliquerait les tests |

## Phase 0 : Recherche

Voir [research.md](./research.md). Decisions principales :

- Reprendre le pattern Miri de reload atomique mais l'adapter a TOMLKit et aux validateurs Roadie.
- Reprendre l'idee menu bar/settings, avec etat derive des services Roadie existants.
- Reprendre restore-on-exit/crash watcher en public APIs uniquement.
- Reprendre detection de fenetres transitoires par roles/subroles AX et service open/save Apple.
- Reprendre persistance par identite stable, mais avec score de confiance et anti-doublon.
- Reporter les animations; interdire SkyLight/MultitouchSupport.

## Phase 1 : Design & Contrats

Voir :

- [data-model.md](./data-model.md)
- [contracts/cli.md](./contracts/cli.md)
- [contracts/config.md](./contracts/config.md)
- [contracts/events.md](./contracts/events.md)
- [contracts/ui.md](./contracts/ui.md)
- [quickstart.md](./quickstart.md)

## Vérification Constitution (Post-Design)

- **Langue francaise**: PASS.
- **ADR**: PASS, tache de creation d'ADR incluse.
- **Tests**: PASS, chaque user story contient des tests independants.
- **Scope**: PASS, animations/private frameworks exclus.
- **Securite**: PASS, les chemins destructifs sont evites; restore safety est idempotent et best-effort.
