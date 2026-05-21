# Plan d'Implémentation : Durcissement de stabilité layout

**Branche** : `main` | **Date** : 2026-05-20 | **Spécification** : [spec.md](./spec.md)
**Type** : reconstruction rétrospective à partir des commits `59425c7`, `87b5934`, `15f5a65`, `1b6fd36`, `5cac231`, `0d17274`, `ce98577`, `05915fc`, `f6b88e6` et du worktree courant.

## Résumé

Roadie a reçu une série de correctifs de stabilité non rattachés à une spec dédiée : respect du `mutableBsp`, suppression des relayouts automatiques contre les commandes utilisateur, exclusion générique des fenêtres système courtes, preview de drop stable, parking invisible des fenêtres cachées, isolation inter-écran et navigation par ordre visible du navrail.

Ce plan formalise a posteriori la stratégie technique réellement livrée : ne pas ajouter un nouveau moteur, mais installer des garde-fous autour du snapshot, du maintainer, des commandes et des previews pour que Roadie ne confonde plus une intention utilisateur avec un drift à corriger.

## Contexte Technique

**Langage/Version** : Swift 6 via Swift Package Manager
**Dépendances principales** : AppKit, Accessibility AX, CoreGraphics, RoadieAX, RoadieCore, RoadieDaemon, RoadieStages, RoadieTiler
**Stockage** : `StageStore`, `LayoutIntentStore`, fichier léger `~/.local/state/roadies/layout-command-activity`, événements Roadie
**Tests** : Swift Testing via `./scripts/test`, `./scripts/with-xcode swift test`, `make build`
**Plateforme cible** : macOS desktop multi-écran, daemon utilisateur `roadied`, CLI `roadie`
**Objectifs de performance** : pas de relayout global inutile après commande ; preview de drop instantanée ; stage switch visible sans attente de relayout ; aucun scan AX lourd dans le chemin layout
**Contraintes** : aucune API privée macOS, aucun SIP off, aucun correctif ad hoc par application, ne jamais rendre une fenêtre inaccessible, ne pas casser les specs 003/007/008/009
**Échelle/Périmètre** : 1 à 3 écrans, dizaines de fenêtres, stages nommées, fenêtres flottantes, popups système, fenêtres cachées, mutable BSP

## Vérification Constitutionnelle

- **Français** : artefacts 010 rédigés en français.
- **Reconstruction rétrospective** : nécessaire car les commits correctifs sont substantiels et transverses.
- **Non-destruction** : toutes les corrections privilégient la préservation de l'état utilisateur et des fenêtres visibles.
- **Simplicité** : une petite primitive `LayoutCommandActivity`, une primitive `HiddenWindowPlacement`, et des garde-fous dans les services existants plutôt qu'un nouveau moteur.
- **Observabilité** : événements de suppression/adoption/propagation pour expliquer pourquoi Roadie n'a pas relayout.
- **Tests** : tests ciblés ajoutés dans les suites existantes, sans créer d'API macOS privée ou flaky.

## Structure du Projet

### Documentation

```text
specs/010-layout-stability-hardening/
├── spec.md
├── plan.md
└── tasks.md
```

### Code Source Concerné

```text
Sources/
├── RoadieDaemon/
│   ├── DaemonSnapshot.swift              # politique tiling, focus caché, intents
│   ├── LayoutMaintainer.swift            # suppression relayout, mutable BSP, parking caché
│   ├── LayoutCommandActivity.swift       # activité commande explicite
│   ├── HiddenWindowPlacement.swift       # parking invisible commun
│   ├── DropPreviewController.swift       # preview stable en drag
│   ├── DisplayParkingService.swift       # récupération stages parkées anciennes
│   ├── StageCommands.swift               # navigation visible et activité commande
│   ├── DesktopCommands.swift             # activité commande et parking caché
│   ├── WindowCommands.swift              # activité commande
│   ├── WindowBookmarkCommands.swift      # parking caché commun
│   ├── WindowContextActions.swift        # parking caché commun
│   ├── RailController.swift              # refresh navrail et visibilité
│   └── StateAudit.swift                  # cohérence post-parking
└── RoadieTiler/
    └── MutableBSPLayoutStrategy.swift    # support de géométrie mutable

Tests/
└── RoadieDaemonTests/
    ├── LayoutMaintainerTests.swift
    ├── SnapshotServiceTests.swift
    ├── DropPreviewEngineTests.swift
    ├── DisplayParkingServiceTests.swift
    ├── PowerUserDesktopCommandTests.swift
    └── TilingPolicyTests.swift
```

## Décisions Techniques

### 1. Intention utilisateur avant auto-correction

Les commandes Roadie qui déplacent, redimensionnent ou changent de stage marquent une activité courte via `LayoutCommandActivity`. Le maintainer peut alors éviter de reprendre la main pendant que macOS applique encore les frames. Cela évite le cas "commande partiellement appliquée puis relayout automatique".

### 2. Mutable BSP comme géométrie adoptable

Le `mutableBsp` n'est pas traité comme un BSP strict à rééquilibrer. Quand les frames observées restent cohérentes, Roadie adopte ou propage la géométrie au lieu de revenir à un arbre théorique.

### 3. Fenêtres flottantes exclues avant membership stage

La politique de tiling s'applique avant de calculer les fenêtres stage-managed. Une fenêtre exclue ne doit plus rester dans la liste effective des fenêtres gérées, sinon elle peut polluer previews, relayout et stage focus.

### 4. Parking invisible centralisé

Le parking bas/gauche historique est remplacé par un parking au bord droit du bureau virtuel, centralisé dans `HiddenWindowPlacement`, avec migration des anciennes positions.

### 5. Écrans indépendants par défaut

Les opérations automatiques de hide, focus restore et relayout ne doivent pas agir sur un autre display sauf commande explicite inter-écran.

### 6. Ordre visible plutôt qu'ID interne

La navigation utilisateur suit l'ordre réellement affiché dans le navrail. Les stages vides/non visibles ne sont pas traversées par les raccourcis visibles.

## Suivi de Complexité

| Écart | Pourquoi c'est nécessaire | Alternative rejetée |
|-------|---------------------------|---------------------|
| Fichier `LayoutCommandActivity` | Les commandes CLI/BTT et le daemon sont des chemins séparés ; il faut partager une activité courte | Timers locaux dans chaque service, trop fragiles et non coordonnés |
| Tolérances d'intent de layout | AX/macOS applique parfois les frames en plusieurs étapes | Exiger une égalité stricte provoque des faux positifs et relayouts |
| Détection générique de fenêtre courte | Popups/progress panels varient par application | Exceptions par app, trop fragiles et contraires à la demande utilisateur |
| Nouveau parking caché | macOS remonte les fenêtres trop proches du bas/gauche | Envoyer plus loin hors écran peut être annulé par macOS |
| Navigation visible filtrée | L'utilisateur pilote le navrail affiché, pas l'état complet | Navigation par ID conserve des stages invisibles entre deux raccourcis |

## Phases Effectives

### Phase 1 : Stabilisation mutable BSP

- Adoption de géométrie mutable.
- Propagation de resize.
- Suppression des relayouts automatiques pendant commandes.
- Tests `LayoutMaintainerTests`.

### Phase 2 : Stabilité drag/drop et previews

- Preview de drop basée sur la frame persistée.
- Ignorer les fenêtres transitoires ou non gérées.
- Tests `DropPreviewEngineTests`.

### Phase 3 : Politique de tiling générique

- Exclusion des fenêtres courtes standard non plein écran.
- Stage membership calculée après politique de tiling.
- Tests `TilingPolicyTests` et `SnapshotServiceTests`.

### Phase 4 : Isolation focus/stage/display

- Protection contre focus caché cross-display après fenêtre manquante.
- Hide stage limité au display concerné.
- Relayout après disparition de fenêtre.
- Tests `SnapshotServiceTests` et `LayoutMaintainerTests`.

### Phase 5 : Parking invisible et recovery display

- `HiddenWindowPlacement`.
- Migration de l'ancien parking bas/gauche.
- Récupération de stages parkées anciennes si l'écran d'origine n'est plus reconnu.
- Tests `LayoutMaintainerTests` et `DisplayParkingServiceTests`.

### Phase 6 : Navigation visible et navrail

- `stage switch-visible`.
- Filtrage des stages non tileables.
- Refresh immédiat du rail.
- Tests `PowerUserDesktopCommandTests`.

## Garde-fous

- Ne jamais ajouter d'exception applicative si un critère AX générique suffit.
- Ne jamais relayout un autre display pour corriger une action scoped sur le display courant.
- Ne jamais considérer une fenêtre flottante comme stage-managed après filtrage.
- Ne jamais remettre en BSP strict une stage explicitement en `mutableBsp`.
- Ne jamais faire dépendre le navrail d'un relayout complet pour refléter un stage switch.
- Ne jamais supprimer un état parking/restored sans chemin de récupération.
