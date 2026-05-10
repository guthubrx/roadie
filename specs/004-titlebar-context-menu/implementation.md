# Journal d'implementation : menu contextuel de barre de titre

## Validation automatique

- `./scripts/with-xcode swift test --filter TitlebarContextMenuTests` : OK, 8 tests.
- `./scripts/with-xcode swift test --filter ConfigTests` : OK, 14 tests sur le filtre.
- `make build` : OK.
- `make test` : OK, 240 tests.

## Validation manuelle

- iTerm2 : a valider.
- Finder : a valider.
- Firefox/Chromium/Electron : a valider.
- Popup/dialogue systeme : a valider.

## Non-regressions a surveiller

- Navrail drag-and-drop : aucun changement volontaire dans le chemin drag/drop.
- Raccourcis Roadie/BTT : aucun changement volontaire dans les commandes de focus, stage switch ou desktop switch.
- Focus/bordure : aucun polling ajoute dans le chemin focus/bordure.

## Notes d'implementation

- Le controleur demarre avec `roadied`, mais reste inerte si `experimental.titlebar_context_menu.enabled = false`.
- Les reglages sont relus au moment du clic droit afin que `roadie config reload` puisse activer ou desactiver le comportement sans redemarrer `roadied`.
- Les actions revalident la fenetre et la destination avant de muter l'etat Roadie.
- Les evenements `ignored` sont limites pour eviter un journal trop bruyant.
