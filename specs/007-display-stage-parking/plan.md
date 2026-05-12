# Plan d'Implémentation : Parking et restauration des stages d'écrans

**Branche** : `031-display-stage-parking` | **Date** : 2026-05-12 | **Spécification** : [spec.md](./spec.md)  
**Entrée** : spécification fonctionnelle issue de `/specs/007-display-stage-parking/spec.md`

## Résumé

Ajouter un mécanisme de parking d'écran : quand un écran disparaît, Roadie ne fusionne plus ses fenêtres dans une stage active et ne supprime plus l'état des scopes absents. Les stages non vides de l'écran disparu sont rapatriées comme stages distinctes sur un écran restant, avec leur origine mémorisée. Quand l'écran revient et qu'il est reconnu avec confiance, Roadie restaure ces stages vers leur écran d'origine en conservant leur état courant.

L'approche technique formalise le correctif conservateur déjà amorcé dans `StageStore`, `DaemonSnapshot`, `StateAudit` et `roadied/main.swift` : remplacer la migration destructive par un modèle explicite `parked/restored`, ajouter une empreinte d'écran logique, stabiliser les événements de changement d'écran, puis appliquer un service dédié de transition de topologie.

## Contexte Technique

**Langage/Version** : Swift 6 via Swift Package Manager  
**Dépendances principales** : AppKit, Accessibility AX, RoadieCore, RoadieDaemon, RoadieAX, RoadieStages, RoadieTiler, TOMLKit  
**Stockage** : état JSON `~/.roadies/stages.json` via `StageStore`; configuration TOML Roadie; logs/events Roadie existants  
**Tests** : Swift Testing via `./scripts/with-xcode swift test`, `make build`, tests unitaires dans `Tests/RoadieDaemonTests`  
**Plateforme cible** : macOS desktop multi-écran, daemon utilisateur `roadied`, CLI `roadie`  
**Type de projet** : application desktop daemon + CLI mono-utilisateur  
**Objectifs de performance** : transition stable en moins de 5 secondes après stabilisation macOS; un seul rapatriement/restauration final par rafale de changements d'écran; pas de travail AX agressif dans le chemin focus/bordure  
**Contraintes** : aucune API privée macOS, aucun SIP off, ne jamais rendre une fenêtre inaccessible, ne pas casser les stages/desktops virtuels, ne pas relancer les oscillations de layout observées sur dialogs et changements d'écran  
**Échelle/Périmètre** : usage local avec 1 à 3 écrans, plusieurs desktops virtuels Roadie, stages nommées, stages vides, pins, groupes et dizaines de fenêtres

## Vérification Constitutionnelle

*Porte qualité : doit passer avant la phase 0 de recherche. Revérifier après la phase 1 de conception.*

- **Français** : les artefacts 007 sont rédigés en français.
- **Cycle SpecKit** : spec 007 présente, plan généré avant tâches et implémentation.
- **Non-destruction** : l'état des écrans absents doit être conservé au lieu d'être purgé par heal/audit.
- **Simplicité** : un service dédié de transition de topologie, sans nouveau moteur de layout ni dépendance externe.
- **Sécurité Roadie** : aucune API privée, aucune modification SkyLight/OSAX, aucun comportement dépendant de SIP.
- **Risque focus/layout** : la stabilisation de changement d'écran doit suspendre les corrections automatiques tant que la topologie n'est pas stable.
- **Observabilité** : chaque parking/restauration doit produire un état et des événements diagnostiquables.
- **Tests obligatoires** : tests unitaires sur parking, restauration, ambiguïté, rafales, scopes stale, stages vides, groupes/focus et non-fusion.

**Porte post-conception** : PASS si les scopes absents sont conservés, si les stages rapatriées portent une origine explicite, si la restauration est conservatrice en cas d'ambiguïté et si aucun chemin ne mélange toutes les fenêtres d'un écran disparu dans une seule stage existante.

## Structure du Projet

### Documentation (cette fonctionnalité)

```text
specs/007-display-stage-parking/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── persistence-display-parking.md
│   ├── transition-behavior.md
│   └── diagnostics-display-parking.md
└── tasks.md
```

### Code Source (racine du dépôt)

```text
Sources/
├── RoadieCore/
│   ├── AutomationEventCatalog.swift       # événements publics display parking/restoration
│   └── AutomationSnapshot.swift           # état exposé si enrichissement snapshot nécessaire
├── RoadieAX/
│   └── SystemSnapshotProvider.swift       # source des DisplaySnapshot live
├── RoadieDaemon/
│   ├── StageStore.swift                   # modèle persistant scopes + origine parking
│   ├── DisplayTopology.swift              # empreinte/reconnaissance logique d'écran
│   ├── DisplayParkingService.swift        # nouveau service de transition topologie
│   ├── StateAudit.swift                   # audit conservateur des scopes absents
│   ├── DaemonSnapshot.swift               # réassignation safe des fenêtres live
│   ├── DaemonHealth.swift                 # heal sans migration destructive
│   ├── LayoutMaintainer.swift             # ne pas relayout pendant période instable
│   ├── StageCommands.swift                # conserver ordre/nom/mode quand stages bougent
│   ├── Formatters.swift                   # sortie diagnostic CLI éventuelle
│   └── EventLog.swift                     # événements de parking/restauration
└── roadied/
    └── main.swift                         # debounce changement d'écran + appel service

Tests/
└── RoadieDaemonTests/
    ├── SnapshotServiceTests.swift
    ├── DisplayTopologyTests.swift
    ├── DisplayParkingServiceTests.swift
    ├── PersistentStageStateTests.swift
    ├── StateAuditTests.swift              # à créer si les checks sortent de SnapshotServiceTests
    └── FormattersTests.swift
```

**Décision de structure** : créer `DisplayParkingService` dans `RoadieDaemon` comme point unique des transitions de topologie. `StageStore` conserve le modèle et les mutations pures; `roadied/main.swift` ne fait que stabiliser les notifications macOS et déclencher le service. Les chemins de snapshot/layout ne doivent pas décider seuls de migrer des scopes, afin d'éviter les corrections implicites qui ont déjà créé des comportements destructeurs.

## Suivi de Complexité

| Écart | Pourquoi c'est nécessaire | Alternative plus simple rejetée car |
|-------|---------------------------|--------------------------------------|
| Empreinte logique d'écran | Les identifiants macOS peuvent changer au rebranchement | Se baser uniquement sur `DisplayID` casse le cas observé où l'écran revient avec un ID différent |
| État explicite de parking | L'utilisateur doit comprendre et restaurer les stages rapatriées | Garder seulement des scopes stale ne suffit pas à savoir où restaurer ni quoi afficher |
| Service dédié de transition | Les changements d'écran déclenchent snapshot, audit, heal et layout | Laisser chaque composant corriger localement recrée des oscillations et migrations contradictoires |
| Debounce topologie | macOS émet plusieurs événements pendant branchement/débranchement | Réagir immédiatement provoque des layouts intermédiaires visibles et parfois faux |

## Phase 0 : Recherche

Voir [research.md](./research.md).

Décisions clés :

- Les scopes d'écrans absents sont conservés comme données d'origine, pas supprimés par audit.
- Le rapatriement crée des stages distinctes sur l'écran cible et marque leur origine.
- La restauration est conservatrice : si l'écran revenu n'est pas reconnu avec confiance, Roadie ne déplace rien automatiquement.
- La période de stabilisation de topologie suspend les ticks de layout/heal destructifs.
- Les stages vides peuvent rester mémorisées sans clutter visible.

## Phase 1 : Conception

Voir :

- [data-model.md](./data-model.md)
- [contracts/persistence-display-parking.md](./contracts/persistence-display-parking.md)
- [contracts/transition-behavior.md](./contracts/transition-behavior.md)
- [contracts/diagnostics-display-parking.md](./contracts/diagnostics-display-parking.md)
- [quickstart.md](./quickstart.md)

## Phase 2 : Approche de Découpage des Tâches

La génération des tâches doit séparer :

1. **Modèle persistant** : empreinte d'écran, origine de stage, état native/parked/restored, compatibilité JSON existante.
2. **Service de transition** : détection disparu/revenu, choix écran cible, parking distinct, restauration conservatrice.
3. **Intégration daemon** : debounce topologie, suspension des ticks layout pendant stabilisation, appel unique du service.
4. **Snapshot/audit** : suppression de la migration destructive, checks warn/fail adaptés, réassignation live sans effacer l'origine.
5. **Diagnostics** : événements et sortie CLI permettant de voir stages natives/rapatriées/restaurées.
6. **Tests unitaires** : parking, restauration, ambiguïté, rafales, stages vides, changements pendant absence, pins/groupes/focus.
7. **Validation manuelle** : quickstart deux écrans, débranchement, travail en mode rapatrié, rebranchement.

## Garde-fous

- Ne jamais supprimer un scope uniquement parce que son écran est absent.
- Ne jamais fusionner toutes les fenêtres d'un écran disparu dans la stage active d'un écran restant.
- Ne jamais restaurer automatiquement vers un écran revenu si la reconnaissance est ambiguë.
- Ne jamais bloquer l'utilisateur : les fenêtres vivantes doivent rester visibles ou récupérables.
- Ne jamais lancer plusieurs transitions concurrentes pour une même rafale de changements d'écran.
- Ne jamais ajouter de polling AX agressif dans le hot path focus/bordure.
- Ne jamais déplacer les stages natives de l'écran restant sauf si l'utilisateur l'a demandé.
- Ne jamais considérer une restauration comme une copie ancienne : c'est la stage rapatriée courante qui revient.
