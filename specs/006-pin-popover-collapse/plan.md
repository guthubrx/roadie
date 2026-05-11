# Plan d'Implémentation : Menu Pin et Repliage

**Branche** : `030-window-pins` | **Date** : 2026-05-11 | **Spécification** : [spec.md](./spec.md)  
**Entrée** : spécification fonctionnelle issue de `/specs/006-pin-popover-collapse/spec.md`

## Résumé

Ajouter, sur les fenêtres déjà pinées, un petit contrôle circulaire bleu qui ouvre un menu compact de style macOS. Ce menu reprend les actions du clic droit de barre de titre, expose l'état de pin courant, et ajoute le repliage en proxy Roadie pour libérer la vue sur les fenêtres situées dessous. L'approche technique garde la fenêtre pinée hors layout automatique, conserve les actions existantes comme source d'autorité, et ajoute uniquement une couche de présentation contrôlée par une configuration expérimentale.

## Contexte Technique

**Langage/Version** : Swift 6 via Swift Package Manager  
**Dépendances principales** : AppKit, Accessibility AX, RoadieCore, RoadieDaemon, RoadieAX, TOMLKit  
**Stockage** : configuration TOML Roadie; état persistant `~/.roadies/stages.json` via `StageStore`; événements Roadie existants  
**Tests** : Swift Testing via `make test` / `./scripts/with-xcode swift test`, tests unitaires dans `Tests/RoadieDaemonTests`  
**Plateforme cible** : macOS desktop multi-écran, daemon utilisateur `roadied`, CLI `roadie`  
**Type de projet** : application desktop daemon + CLI mono-utilisateur  
**Objectifs de performance** : apparition du bouton et du menu sans latence perceptible; repliage/restauration sous 1 seconde; aucun polling agressif supplémentaire dans le chemin focus/bordure  
**Contraintes** : aucune API privée macOS, aucun SIP off, aucune injection dans les fenêtres applicatives, ne pas couvrir les contrôles natifs, ne pas relancer les bugs récents de focus/stage/bordures  
**Échelle/Périmètre** : usage local avec plusieurs écrans, desktops virtuels Roadie, stages et dizaines de fenêtres; première version limitée aux fenêtres déjà pinées

## Vérification Constitutionnelle

*Porte qualité : doit passer avant la phase 0 de recherche. Revérifier après la phase 1 de conception.*

- **Français** : artefacts 006 rédigés en français.
- **Cycle SpecKit** : spec 006 présente, plan généré avant tâches et implémentation.
- **Non-intrusion** : menu Roadie séparé; aucune modification des menus ou barres de titre natives.
- **Simplicité** : un contrôleur de présentation et un état de présentation de pin, sans nouveau moteur de layout.
- **Sécurité Roadie** : aucune API privée, aucun SIP off, pas de dépendance à SkyLight/OSAX.
- **Risque layout/focus** : bouton, menu et proxy ne doivent pas devenir des fenêtres gérées par le tiler ni provoquer de changement de stage/focus.
- **Tests obligatoires** : tests de config, placement sûr, menu, état de repliage, restauration, non-régression fenêtres non pinées.

**Porte post-conception** : PASS si le bouton et le proxy restent des overlays Roadie exclus du tiling, si les actions réutilisent `WindowContextActions`, et si le contrôle est omis plutôt que risqué quand le placement est ambigu.

## Structure du Projet

### Documentation (cette fonctionnalité)

```text
specs/006-pin-popover-collapse/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── config-pin-popover.md
│   ├── ui-pin-popover.md
│   └── events-pin-popover.md
└── tasks.md
```

### Code Source (racine du dépôt)

```text
Sources/
├── RoadieCore/
│   ├── Config.swift                      # configuration experimental.pin_popover
│   └── AutomationEventCatalog.swift      # événements publics pin_popover/window.pin_collapsed
├── RoadieDaemon/
│   ├── StageStore.swift                  # état persistant de présentation des pins
│   ├── DaemonSnapshot.swift              # exposition diagnostic de l'état de présentation
│   ├── LayoutMaintainer.swift            # ignore/restaure correctement les pins repliés
│   ├── WindowContextActions.swift        # actions existantes réutilisées
│   ├── TitlebarContextMenuController.swift # source des destinations/actions existantes
│   ├── PinPopoverController.swift        # nouveau contrôleur bouton + menu + proxy
│   └── Formatters.swift                  # diagnostic CLI si nécessaire
└── roadied/
    └── main.swift                        # démarrage conditionnel du contrôleur

Tests/
└── RoadieDaemonTests/
    ├── ConfigTests.swift
    ├── PersistentStageStateTests.swift
    ├── SnapshotServiceTests.swift
    ├── LayoutMaintainerTests.swift
    ├── TitlebarContextMenuTests.swift
    └── PinPopoverTests.swift
```

**Décision de structure** : créer un contrôleur dédié `PinPopoverController` pour séparer cette UI visible permanente du menu clic droit existant. Les actions de déplacement et de pin restent centralisées dans `WindowContextActions`; le contrôleur ne doit être qu'une couche d'affichage et d'invocation. L'état de repliage est rattaché au modèle persistant des pins pour survivre aux snapshots et aux changements de stage/desktop.

## Suivi de Complexité

| Écart | Pourquoi c'est nécessaire | Alternative plus simple rejetée car |
|-------|---------------------------|--------------------------------------|
| Overlay visible attaché à la fenêtre pinée | L'utilisateur a besoin d'un point d'entrée découvrable sans clic droit | Utiliser uniquement le menu clic droit ne résout pas la découvrabilité |
| Proxy Roadie de repliage | Les fenêtres applicatives imposent souvent une taille minimale et réagissent mal au vrai "shade" | Redimensionner réellement les apps créerait des comportements différents selon Electron, SwiftUI ou AppKit |
| État de présentation persistant | Un pin replié doit rester cohérent entre changements de stage/desktop | Garder l'état uniquement en mémoire le ferait disparaître ou diverger après refresh/relance |
| Contrôleur dédié | Le navrail, les bordures et le menu clic droit ont déjà des responsabilités sensibles | Mélanger cette UI dans `BorderController` ou `RailController` augmenterait le risque de régression |

## Phase 0 : Recherche

Voir [research.md](./research.md).

Décisions clés :

- Bouton et proxy sont des overlays Roadie, pas une injection dans la fenêtre applicative.
- Le repliage v1 utilise un proxy Roadie et cache/déplace la vraie fenêtre selon les mécanismes Roadie existants, sans redimensionnement réel façon "shade".
- La configuration vit sous `[experimental.pin_popover]`, activable indépendamment du menu clic droit.
- Les actions du menu réutilisent `WindowContextActions` et les destinations existantes.
- Le placement du bouton est conservateur : en cas de doute, ne pas afficher.

## Phase 1 : Conception

Voir :

- [data-model.md](./data-model.md)
- [contracts/config-pin-popover.md](./contracts/config-pin-popover.md)
- [contracts/ui-pin-popover.md](./contracts/ui-pin-popover.md)
- [contracts/events-pin-popover.md](./contracts/events-pin-popover.md)
- [quickstart.md](./quickstart.md)

## Phase 2 : Approche de Découpage des Tâches

La génération des tâches doit séparer :

1. **Configuration** : section expérimentale, validation TOML, désactivation complète du bouton.
2. **Modèle de présentation** : état visible/replié, frame précédent, identité du proxy.
3. **Placement sûr** : calcul pur de position du bouton et règles d'omission.
4. **Contrôleur UI** : bouton circulaire bleu, menu compact, proxy replié.
5. **Actions** : réutilisation des actions de titre existantes et nouvelles actions replier/restaurer.
6. **Événements/diagnostic** : menu affiché, action, repliage, restauration, placement omis.
7. **Tests et quickstart** : validation des scénarios de découverte, repliage/restauration et non-régression.

## Garde-fous

- Ne jamais injecter de bouton dans la vraie barre de titre de l'application.
- Ne jamais afficher le bouton si son placement couvre un contrôle natif probable.
- Ne jamais faire entrer le bouton, le menu ou le proxy dans le tiling.
- Ne jamais changer la stage active ou le focus seulement parce que le bouton/menu/proxy est visible.
- Ne jamais dupliquer la logique de déplacement stage/desktop/display hors de `WindowContextActions`.
- Ne jamais transformer une fenêtre non pinée en pin ou float par simple affichage du contrôleur.
- Ne jamais rendre le repliage irréversible : le proxy doit toujours permettre de restaurer ou dépinner.
