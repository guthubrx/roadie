# Implementation : Menu Pin et Repliage

## 2026-05-11

- Ajout de la configuration `[experimental.pin_popover]`, désactivée par défaut.
- Ajout d'un état persistant de présentation pour les pins : `visible` ou `collapsed`.
- Ajout d'un contrôleur Roadie isolé qui affiche un bouton sur les fenêtres pinées et un proxy compact pour les fenêtres repliées.
- Les actions de déplacement et de pin réutilisent `WindowContextActions`.
- `LayoutMaintainer` ne restaure plus automatiquement une fenêtre volontairement repliée.
- `roadie windows list` affiche maintenant la présentation du pin.

## Validations automatiques

- `./scripts/with-xcode swift test --filter PinPopoverTests` : OK.
- Tests ciblés PinPopover / menu barre de titre / snapshot pin / snapshot général : OK.
- `make build` : OK.
- `make test` : OK, 297 tests.

## Validations manuelles

- Bouton visible : à valider après relance de l'application.
- Repliage/restauration 20 cycles : à valider après relance de l'application.
- Changement stage/desktop avec pin replié : à valider après relance de l'application.
