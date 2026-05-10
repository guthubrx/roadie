# Implementation Notes: Stage Display Move

## Etat

Implementation appliquee sur la branche `028-stage-display-move`.

## Livrable

- Configuration `[focus].stage_move_follows_focus`.
- Primitive daemon unique `moveStageToDisplay(...)`.
- CLI `roadie stage move-to-display N|left|right|up|down [--follow|--no-follow]`.
- Menu contextuel navrail par clic droit sur une carte de stage.
- Protection collision d'ID : une stage cible non vide n'est jamais supprimee.
- Tests unitaires dedies dans `StageDisplayMoveTests`.
- Documentation FR/EN et README mis a jour.

## Validation

- `./scripts/with-xcode swift test --filter StageDisplayMoveTests` passe avec 10 tests.
- `./scripts/with-xcode swift test --filter ConfigTests` passe avec 11 tests.
- `make build` passe.
- `swift build --target RoadieDaemonTests` compile les tests RoadieDaemon, dont `StageDisplayMoveTests.swift`.
- `swift build --target roadie` et `swift build --target roadied` passent.
- `swift test --filter StageDisplayMoveTests` sans wrapper Xcode echoue au link avant execution des tests avec :

```text
ld: unknown option: -no_warn_duplicate_libraries
```

Le probleme est note dans `quickstart.md`; les scenarios manuels multi-ecran restent a executer apres resolution du linker et relance de l'app.
