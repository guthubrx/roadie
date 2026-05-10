# Plan d'Implémentation : Menu Contextuel de Barre de Titre

**Branche** : `029-titlebar-context-menu` | **Date** : 2026-05-10 | **Spécification** : [spec.md](./spec.md)  
**Entrée** : spécification fonctionnelle issue de `/specs/004-titlebar-context-menu/spec.md`

## Résumé

Ajouter un menu Roadie experimental, declenche uniquement par clic droit dans une zone probable de barre de titre, pour envoyer la fenetre cible vers une autre stage, un autre desktop Roadie ou un autre ecran. L'approche technique isole cette logique dans un controleur dedie, desactive par defaut via TOML, avec detection conservative : en cas de doute, Roadie ne capture pas le clic droit et laisse l'application le traiter.

## Contexte Technique

**Langage/Version** : Swift 6 via Swift Package Manager  
**Dépendances principales** : AppKit, Accessibility AX, RoadieCore, RoadieDaemon, RoadieAX, TOMLKit  
**Stockage** : configuration TOML Roadie, état local `~/.roadies/` pour stages/desktops/events  
**Tests** : Swift Testing via `./scripts/with-xcode swift test`, tests unitaires dans `Tests/RoadieDaemonTests`  
**Plateforme cible** : macOS desktop multi-ecran, daemon utilisateur `roadied`, CLI `roadie`  
**Type de projet** : application desktop daemon + CLI mono-utilisateur  
**Objectifs de performance** : detection clic droit et affichage menu sans latence perceptible ; aucune mesure ou boucle ajoutee dans le hot path focus/bordure  
**Contraintes** : aucune API privee macOS, aucun SIP off, fonctionnalite desactivee par defaut, ne pas intercepter les clics droits du contenu applicatif, ne pas casser le navrail ou les raccourcis existants  
**Échelle/Périmètre** : usage local avec plusieurs ecrans, desktops virtuels Roadie, stages et dizaines de fenetres

## Vérification Constitutionnelle

*Porte qualité : doit passer avant la phase 0 de recherche. Revérifier après la phase 1 de conception.*

- **Francais** : artefacts 004 en francais.
- **Cycle SpecKit** : specification 004 presente, plan genere avant tasks/implementation.
- **Non-intrusion** : la fonctionnalite reste experimentale, desactivee par defaut, et fail-open.
- **Simplicite** : controleur dedie et reutilisation des services existants au lieu d'un nouveau modele de fenetres.
- **Qualite / anti-boucle** : tests unitaires sur detection, config et destinations avant integration manuelle.
- **Securite Roadie** : aucune API privee, aucune modification du menu natif des applications.

**Porte post-conception** : PASS sous reserve que l'implementation garde la capture conditionnelle et ne consomme jamais un clic hors zone eligible.

## Structure du Projet

### Documentation (cette fonctionnalité)

```text
specs/004-titlebar-context-menu/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── config-titlebar-context-menu.md
│   ├── ui-titlebar-context-menu.md
│   └── events-titlebar-context-menu.md
└── tasks.md
```

### Code Source (racine du dépôt)

```text
Sources/
├── RoadieCore/
│   └── Config.swift                     # section experimental.titlebar_context_menu
├── RoadieDaemon/
│   ├── TitlebarContextMenuController.swift
│   ├── WindowContextActions.swift
│   ├── RailController.swift             # reference existante pour pattern NSMenu/right-click
│   ├── StageCommands.swift              # assign window vers stage
│   ├── DesktopCommands.swift            # assign window vers desktop
│   ├── WindowCommands.swift             # send window vers display
│   └── DaemonSnapshot.swift             # source snapshot/window scopes
└── roadied/
    └── main.swift                       # demarrage du controleur si option active

Tests/
└── RoadieDaemonTests/
    ├── TitlebarContextMenuTests.swift
    └── ConfigTests.swift
```

**Décision de structure** : ajouter un controleur dedie au menu de barre de titre dans `RoadieDaemon` pour eviter de melanger cette capture globale avec le navrail. La configuration reste dans `RoadieCore`. Les actions appellent les services deja responsables des deplacements fenetre/stage/desktop/display.

## Suivi de Complexité

| Écart | Pourquoi c'est nécessaire | Alternative plus simple rejetée car |
|-----------|------------|--------------------------------------|
| Detection heuristique de barre de titre | macOS et les apps ne fournissent pas une definition uniforme exploitable pour toutes les fenetres | Intercepter tous les clics droits sur fenetre casserait les menus internes des applications |
| Controleur global dedie | Le clic droit arrive hors navrail et doit observer la position souris globale | Ajouter cette responsabilite a `RailController` couplerait deux zones UI sans lien fonctionnel |

## Phase 0 : Recherche

Voir [research.md](./research.md).

Décisions clés :

- Fonctionnalite dans `[experimental.titlebar_context_menu]`, desactivee par defaut.
- Detection conservative par bande haute configurable, marges d'exclusion et restriction aux fenetres gerees.
- En cas de doute, ne pas afficher le menu et laisser le clic droit a l'application.
- Menu Roadie separe du menu natif de l'application ; aucune injection dans les menus applicatifs.
- Actions routees vers services existants, avec petits adaptateurs si les services actuels ne ciblent que la fenetre active.

## Phase 1 : Conception

Voir :

- [data-model.md](./data-model.md)
- [contracts/config-titlebar-context-menu.md](./contracts/config-titlebar-context-menu.md)
- [contracts/ui-titlebar-context-menu.md](./contracts/ui-titlebar-context-menu.md)
- [contracts/events-titlebar-context-menu.md](./contracts/events-titlebar-context-menu.md)
- [quickstart.md](./quickstart.md)

## Phase 2 : Approche de Découpage des Tâches

La generation des taches doit separer :

1. **Configuration** : section experimentale TOML, valeurs par defaut, validation.
2. **Detection pure** : fonctions testables de hit-test titlebar, exclusions, fenetre cible.
3. **Interface menu** : controleur AppKit avec clic droit global et menu conditionnel.
4. **Actions fenetre** : destinations stage/desktop/display, no-op destination courante, echecs propres.
5. **Observabilite** : evenements pour menu affiche, ignore, action executee, action echouee.
6. **Docs et validation** : quickstart manuel, docs FR/EN, tests unitaires et essais avec apps standard.

## Garde-fous

- Ne jamais consommer un clic droit si la fonctionnalite est desactivee.
- Ne jamais consommer un clic droit hors zone eligible.
- Ne jamais afficher de menu pour fenetres non gerees, popups, dialogues systeme ou fenetres transitoires.
- Ne jamais deplacer une fenetre si la cible disparait entre ouverture du menu et selection.
- Ne jamais ajouter de delai, polling agressif ou capture continue dans le chemin focus/bordure.
