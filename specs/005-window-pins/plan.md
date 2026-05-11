# Plan d'Implémentation : Pins de Fenêtres

**Branche** : `030-window-pins` | **Date** : 2026-05-11 | **Spécification** : [spec.md](./spec.md)  
**Entrée** : spécification fonctionnelle issue de `/specs/005-window-pins/spec.md`

## Résumé

Ajouter des actions de pin depuis le menu contextuel de barre de titre pour rendre une fenêtre visible soit sur toutes les stages du desktop courant, soit sur tous les desktops Roadie du même écran. L'approche technique ajoute un état de pin explicite dans l'état persistant des stages, réutilise le menu de barre de titre existant, et garde les fenêtres pinées hors du calcul de layout pour éviter les déplacements parasites.

## Contexte Technique

**Langage/Version** : Swift 6 via Swift Package Manager  
**Dépendances principales** : AppKit, Accessibility AX, RoadieCore, RoadieDaemon, RoadieAX, RoadieStages, TOMLKit  
**Stockage** : état local `~/.roadies/stages.json` via `StageStore`; événements Roadie existants  
**Tests** : Swift Testing via `make test` / `./scripts/with-xcode swift test`, tests unitaires dans `Tests/RoadieDaemonTests`  
**Plateforme cible** : macOS desktop multi-écran, daemon utilisateur `roadied`, CLI `roadie`  
**Type de projet** : application desktop daemon + CLI mono-utilisateur  
**Objectifs de performance** : changement de stage/desktop sans latence perceptible; pas de duplication de fenêtre dans l'état; complexité linéaire sur le nombre de fenêtres suivies  
**Contraintes** : aucune API privée macOS, aucun SIP off, ne pas relancer les bugs récents de bordures/stage, ne pas re-tiler une fenêtre pinée, ne pas pinner de fenêtre transitoire  
**Échelle/Périmètre** : usage local avec plusieurs écrans, desktops virtuels Roadie, stages et dizaines de fenêtres

## Vérification Constitutionnelle

*Porte qualité : doit passer avant la phase 0 de recherche. Revérifier après la phase 1 de conception.*

- **Français** : les artefacts 005 sont rédigés en français.
- **Cycle SpecKit** : spécification 005 présente, plan généré avant tâches et implémentation.
- **Non-intrusion** : aucune injection dans les menus applicatifs; le point d'entrée reste le menu Roadie déjà expérimental.
- **Simplicité** : état de pin ajouté au modèle persistant existant, sans nouveau daemon ni store parallèle.
- **Sécurité Roadie** : aucune API privée, aucune dépendance à SkyLight ou OSAX.
- **Risque layout/focus** : les fenêtres pinées restent hors layout automatique; les changements de visibilité doivent être traités explicitement pour ne pas activer des stages/desktops par effet de bord.
- **Tests obligatoires** : tests unitaires sur modèle d'état, snapshot, hide inactive, menu, événements et régressions non-pinned.

**Porte post-conception** : PASS sous réserve que l'implémentation conserve une source d'autorité unique pour le pin et ne duplique jamais une fenêtre dans plusieurs stages.

## Structure du Projet

### Documentation (cette fonctionnalité)

```text
specs/005-window-pins/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── persistence-window-pins.md
│   ├── ui-titlebar-window-pins.md
│   └── events-window-pins.md
└── tasks.md
```

### Code Source (racine du dépôt)

```text
Sources/
├── RoadieCore/
│   ├── AutomationEventCatalog.swift      # événements publics window.pin_*
│   └── Config.swift                      # pas de nouvelle config obligatoire
├── RoadieDaemon/
│   ├── StageStore.swift                  # état persistant des pins
│   ├── DaemonSnapshot.swift              # scope visible/effectif des fenêtres pinées
│   ├── LayoutMaintainer.swift            # hide inactive compatible pins
│   ├── WindowContextActions.swift        # actions pin/unpin depuis menu
│   ├── TitlebarContextMenuController.swift
│   └── Formatters.swift                  # sortie de diagnostic si nécessaire
└── roadie/
    └── main.swift                        # commandes CLI uniquement si exposées par tâches

Tests/
└── RoadieDaemonTests/
    ├── PersistentStageStateTests.swift
    ├── SnapshotServiceTests.swift
    ├── LayoutMaintainerTests.swift
    ├── TitlebarContextMenuTests.swift
    └── AutomationEventTests.swift
```

**Décision de structure** : stocker les pins dans `PersistentStageState` pour les faire voyager avec les stages/desktops/displays existants. Les actions utilisateur restent dans `WindowContextActions`, car elles prolongent le menu de barre de titre. La logique de visibilité doit être appliquée dans `SnapshotService` et `LayoutMaintainer`, là où Roadie décide déjà quelles fenêtres sont visibles ou cachées.

## Suivi de Complexité

| Écart | Pourquoi c'est nécessaire | Alternative plus simple rejetée car |
|-------|---------------------------|--------------------------------------|
| État de pin distinct des membres de stage | Une fenêtre pinée doit être visible dans plusieurs contextes sans être dupliquée | Ajouter la fenêtre comme membre de chaque stage recréerait les bugs de duplication, focus et layout |
| Adaptation du hide inactive | Une fenêtre pinée peut avoir un scope d'origine différent du contexte actif tout en devant rester visible | Laisser `hideInactiveStageWindows` inchangé cacherait immédiatement les pins |
| Éligibilité stricte | Les popups et panneaux système ont déjà causé des boucles de layout | Permettre de pinner toute fenêtre sous le curseur rendrait la fonctionnalité instable |

## Phase 0 : Recherche

Voir [research.md](./research.md).

Décisions clés :

- Le pin est un état persistant de fenêtre, pas une duplication de membership.
- Les scopes supportés sont `desktop` et `all_desktops` sur le même display.
- Les fenêtres pinées sont exclues du layout tout en restant suivies par Roadie.
- Les actions de pin/unpin réutilisent le menu contextuel de barre de titre.
- Les fenêtres transitoires restent exclues via les mêmes garde-fous que le menu existant.

## Phase 1 : Conception

Voir :

- [data-model.md](./data-model.md)
- [contracts/persistence-window-pins.md](./contracts/persistence-window-pins.md)
- [contracts/ui-titlebar-window-pins.md](./contracts/ui-titlebar-window-pins.md)
- [contracts/events-window-pins.md](./contracts/events-window-pins.md)
- [quickstart.md](./quickstart.md)

## Phase 2 : Approche de Découpage des Tâches

La génération des tâches doit séparer :

1. **Modèle persistant** : `PersistentWindowPin`, `WindowPinScope`, migration/backward compatibility et nettoyage des fenêtres fermées.
2. **Service de décision** : helpers purs pour savoir si une fenêtre pinée doit être visible dans le contexte actif.
3. **Snapshot/visibilité** : intégration dans `SnapshotService` et `LayoutMaintainer` sans duplication de fenêtre.
4. **Menu de barre de titre** : ajout des actions pin/unpin et état courant visible.
5. **Événements** : `window.pin_added`, `window.pin_removed`, `window.pin_scope_changed`, `window.pin_pruned`.
6. **Tests de régression** : stages/desktops non-pinned inchangés, fenêtres flottantes inchangées, popups non éligibles.
7. **Docs/quickstart** : exemples utilisateur FR/EN si l'implémentation expose le comportement.

## Garde-fous

- Ne jamais ajouter une fenêtre pinée comme membre de plusieurs stages.
- Ne jamais faire entrer une fenêtre pinée dans `ApplyPlan`.
- Ne jamais changer le focus ou la stage active au moment du pin, sauf action utilisateur explicite.
- Ne jamais rendre visible un pin `desktop` sur un autre desktop.
- Ne jamais rendre visible un pin `all_desktops` sur un autre display.
- Ne jamais proposer le pin sur une popup, un dialogue, un panneau système ou une fenêtre non gérée.
- Ne jamais casser le comportement des fenêtres non pinées : leur stage/desktop/layout restent l'autorité.
