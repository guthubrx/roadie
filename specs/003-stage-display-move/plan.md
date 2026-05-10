# Implementation Plan: Stage Display Move

**Branch**: `028-stage-display-move` | **Date**: 2026-05-10 | **Spec**: [spec.md](./spec.md)  
**Input**: Feature specification from `/specs/003-stage-display-move/spec.md`
**Isolation**: developpement effectue sur la branche isolee `028-stage-display-move`; aucun worktree separe n'a ete cree pour cette session.

## Summary

Permettre a Roadie de deplacer une stage entiere d'un ecran a un autre, depuis la CLI ou depuis le menu contextuel du navrail. La fonctionnalite etend la commande existante `stage move-to-display` pour accepter les directions, le deplacement d'une stage inactive depuis le rail, et une preference utilisateur qui decide si le focus suit la stage deplacee.

Le plan garde la mutation de state dans `StageCommands`, reutilise `DisplayTopology` pour resoudre les directions, et ajoute une couche de contrat autour de trois points sensibles : pas de perte de fenetres si un identifiant de stage existe deja sur l'ecran cible, pas de focus force quand la configuration demande de rester sur l'ecran source, et menu rail limite aux cibles valides.

## Technical Context

**Language/Version**: Swift 6.0 via Swift Package Manager  
**Primary Dependencies**: AppKit, Accessibility AX, SwiftUI/AppKit pour le navrail, TOMLKit, modele RoadieCore/RoadieDaemon/RoadieStages existant  
**Storage**: state Roadie sous `~/.roadies/` (`stages.json`, `layout-intents.json`, `events.jsonl`) et configuration TOML Roadie  
**Testing**: `swift test`, tests Swift Testing dans `Tests/RoadieDaemonTests` et `Tests/RoadieCoreTests`  
**Target Platform**: macOS desktop multi-ecran, daemon utilisateur `roadied`, CLI `roadie`  
**Project Type**: application desktop/daemon/CLI mono-utilisateur  
**Performance Goals**: deplacement visible des fenetres de stage en moins d'une seconde pour les cas courants, sans boucle de reactivation et sans recalcul global inutile  
**Constraints**: aucune API privee macOS, aucun SIP off, aucune fusion implicite de stages, comportement atomique cote state avant action AX, compatibilite avec les commandes existantes par ID ou position visible  
**Scale/Scope**: usage local avec plusieurs ecrans, plusieurs desktops virtuels, plusieurs stages par ecran, dizaines de fenetres

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **SpecKit obligatoire** : spec `003-stage-display-move` presente et branche feature `028-stage-display-move` active.
- **Francais** : artefacts spec/plan/tasks en francais, avec noms techniques conserves quand ils sont contractuels.
- **Simplicite** : extension des services existants (`StageCommands`, `DisplayTopology`, `RailController`) plutot qu'un nouveau service de deplacement.
- **Atomicite** : snapshot state modifie et sauve avant effets AX ; en cas de cible invalide, aucune mutation.
- **Non-regression bordures/focus** : ne pas reintroduire de reactivation asynchrone agressive ; le focus ne doit changer que si la politique de follow le demande.
- **Tests** : couvrir les mutations de state, les directions, les collisions d'identifiants et la preference de follow avant merge.

**Post-Design Gate**: PASS sous reserve que l'implementation garde la logique de mouvement centralisee et que les actions UI appellent la meme primitive que la CLI.

## Project Structure

### Documentation (this feature)

```text
specs/003-stage-display-move/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── cli-stage-display-move.md
│   ├── config-stage-display-move.md
│   └── rail-context-menu.md
└── checklists/
    └── requirements.md
```

### Source Code (repository root)

```text
Sources/
├── roadie/
│   └── main.swift                       # parsing CLI stage move-to-display
├── RoadieCore/
│   └── Config.swift                     # preference focus.stage_move_follows_focus
├── RoadieDaemon/
│   ├── StageCommands.swift              # primitive unique de deplacement stage->display
│   ├── DisplayTopology.swift            # resolution directionnelle deja existante
│   └── RailController.swift             # menu contextuel et action rail
└── RoadieStages/
    └── RoadieState.swift                # modele stage/display existant

Tests/
├── RoadieCoreTests/
└── RoadieDaemonTests/
```

**Structure Decision**: conserver les frontieres actuelles. `RoadieCore` porte la preference de configuration ; `RoadieDaemon` porte la mutation de state et les actions du rail ; `roadie/main.swift` reste une facade de parsing et de sortie utilisateur.

## Phase 0: Research

Voir [research.md](./research.md).

Decisions cles :

- La CLI accepte les index d'ecran existants et les directions `left|right|up|down`.
- La preference de follow vit dans `[focus]` sous une cle dediee, pour ne pas melanger avec le focus follow mouse ou l'assignation de fenetres.
- Les collisions d'identifiant de stage sur l'ecran cible ne doivent jamais supprimer une stage existante non vide.
- Le menu contextuel du rail appelle la meme primitive que la CLI, avec source display et stage explicites.

## Phase 1: Design

Voir :

- [data-model.md](./data-model.md)
- [contracts/cli-stage-display-move.md](./contracts/cli-stage-display-move.md)
- [contracts/config-stage-display-move.md](./contracts/config-stage-display-move.md)
- [contracts/rail-context-menu.md](./contracts/rail-context-menu.md)
- [quickstart.md](./quickstart.md)

## Phase 2: Task Planning Approach

La generation de taches doit separer :

1. **Configuration** : ajouter la preference `focus.stage_move_follows_focus` et ses tests de decode/default.
2. **Primitive daemon** : extraire une operation unique `moveStageToDisplay` reutilisable par active stage, direction et rail.
3. **CLI** : etendre `stage move-to-display` aux directions et aux overrides `--follow|--no-follow`.
4. **Rail UI** : ajouter le menu contextuel clic droit et l'action d'envoi d'une stage inactive.
5. **Hardening** : collisions de stage ID, ecran source vide, cible disparue, absence de second ecran, echec partiel AX.
6. **Documentation/tests** : quickstart utilisateur, README si commande publique, tests unitaires et scenario manuel multi-ecran.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Primitive de deplacement explicite avec source stage/display | Le rail doit deplacer une stage inactive sans l'activer avant | Reutiliser uniquement "active stage" changerait le focus et casserait l'US3 |
| Gestion explicite des collisions d'ID | Plusieurs ecrans peuvent contenir des stages portant le meme ID | Supprimer la stage cible homonyme risquerait une perte de fenetres |
| Override CLI `--follow/--no-follow` | Tester et depanner sans modifier le TOML | Une preference globale seule rend les tests multi-scenarios plus lourds |

## Progress Tracking

**Phase Status**:

- [x] Phase 0: Research complete
- [x] Phase 1: Design complete
- [x] Phase 2: Task planning approach defined
- [x] Phase 3: Tasks generated
- [x] Phase 4: Implementation
- [ ] Phase 5: Validation

**Gate Status**:

- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented
