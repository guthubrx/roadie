# Implementation: Roadie Target Mode

## Synthese

La spec 009 livre maintenant le socle Target Mode et son extension en 10 etapes
sous forme Roadie-native :

- inventaire stable des cibles Roadie;
- inspection JSON et texte;
- activation par label ou ID;
- picker par recherche;
- etat overlay/labels-only consommable par un futur overlay ou par BTT/Karabiner;
- app targets experimentaux avec click, double-click et right-click;
- focus des bookmarks via le meme chemin Target Mode;
- documentation FR/EN des limites non encore livrees.

## Taches completees

### T001-T030 - Socle Target Mode

- **Statut** : Complete
- **Fichiers principaux** :
  - `Sources/RoadieDaemon/TargetHintService.swift`
  - `Sources/RoadieDaemon/TargetInspectionService.swift`
  - `Sources/RoadieDaemon/AppTargetQueryService.swift`
  - `Sources/roadie/main.swift`
- **Tests** : inclus dans la suite complete.

### T031-T034 - Picker clavier

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/TargetHintService.swift`
  - `Sources/RoadieDaemon/Formatters.swift`
  - `Sources/roadie/main.swift`
  - `Tests/RoadieDaemonTests/TargetHintServiceTests.swift`
- **Tests executes** :
  - `./scripts/with-xcode swift test --filter TargetHintServiceTests --filter AppTargetQueryServiceTests`

### T035-T038 - Actions enrichies

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/AppTargetQueryService.swift`
  - `Sources/RoadieDaemon/TargetHintService.swift`
  - `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`
  - `Tests/RoadieDaemonTests/TargetHintServiceTests.swift`
- **Notes** : les app targets supportent `click`, `double-click` et `right-click`; les bookmarks supportent le focus via `targets activate`.

### T039-T041 - Overlay-state labels-only

- **Statut** : Complete
- **Fichiers modifies** :
  - `Sources/RoadieDaemon/TargetHintService.swift`
  - `Sources/RoadieDaemon/Formatters.swift`
  - `Sources/roadie/main.swift`
- **Notes** : `targets show --json` retourne un `TargetOverlayState` derive du meme inventaire que `targets list`.

### T042-T045 - Inspecteur, documentation et limites

- **Statut** : Complete
- **Fichiers modifies** :
  - `docs/fr/features.md`
  - `docs/en/features.md`
  - `docs/fr/cli.md`
  - `docs/en/cli.md`
  - `README.fr.md`
  - `README.md`
- **Notes** : les limites Vimac/Homerow non livrees sont documentees comme futures ou experimentales.

### T046-T050 - Analyse et validation

- **Statut** : Complete
- **Tests executes** :
  - `./scripts/with-xcode swift test` : 352 tests OK
  - `make build` : OK
- **Smoke CLI** :
  - `./scripts/roadie targets list --max 3`
  - `./scripts/roadie targets show --json --labels-only --max 2`
  - `./scripts/roadie targets pick zzz-nothing-here --json --max 5`

## REX - Retour d'Experience

**Date** : 2026-05-17
**Taches completees** : 68/68

### Ce qui a bien fonctionne

- Le modele `RoadieTarget` existant a permis d'ajouter `pick` et `show` sans toucher au moteur de layout.
- Les app targets restent isoles derriere un provider, ce qui rend les tests simples et evite les regressions sur les stages.
- Les labels, le picker et l'overlay-state partagent le meme inventaire; il n'y a pas de second moteur de labels.

### Difficultes rencontrees

- Le vrai overlay graphique est plus risque que le contrat overlay-state : il touche AppKit, focus et z-order. Il est donc volontairement decouple.
- Les app targets peuvent etre lents selon les applications. La limite reste geree par `max_targets` et `timeout_ms`.

### Connaissances acquises

- Les bookmarks existaient deja comme primitive solide, mais le Target Mode ne routait pas encore leur action `focus`.
- Le picker doit refuser l'ambiguite au lieu de choisir arbitrairement, sinon il reproduit les problemes de stages inattendues.

### Recommandations pour le futur

- Implementer l'overlay graphique uniquement comme consommateur de `TargetOverlayState`.
- Brancher BTT/Karabiner sur `targets show`, `targets pick` et `targets activate`, sans faire de BTT une dependance Roadie.
- Garder le scroll-mode Vimac derriere `experimental.app_targets` tant que les perfs AX ne sont pas observees en usage reel.
- Les capacites Target Mode sont maintenant separees dans `[experimental.target_mode]` :
  socle CLI, picker, overlay futur, clics applicatifs et scroll-mode peuvent etre
  actives ou coupes independamment. Les clics applicatifs restent desactives par
  defaut meme si la decouverte AX est activee.

## Extension Neru / record-replay

**Date** : 2026-05-17
**Taches completees** : T057-T068

### Livré

- `TargetGridService` : grille récursive configurable, rapports JSON, conversion en cibles overlay, actions click/double-click/right-click/move/scroll/drag.
- `TargetMacroService` : modèles de recording, capture par event tap, enrichissement cible Roadie/AX, chemin de grille fallback, persistance JSON, replay target-first puis coordonnées.
- AX boost : parcours optionnel de `AXVisibleChildren`, `AXChildrenInNavigationOrder`, `AXRows`, `AXColumns`, `AXContents`, `AXTabs`, avec déduplication et profondeur maximale.
- Config : `[experimental.target_grid]`, `[experimental.target_record]`, extensions `[experimental.app_targets]`.
- CLI : `roadie grid ...` et `roadie record ...`.
- Tests : `TargetGridServiceTests`, `TargetMacroServiceTests`, extension `ConfigTests`.

### Validations

- `make build` : OK.
- `./scripts/with-xcode swift test --filter TargetGridServiceTests --filter TargetMacroServiceTests --filter ConfigTests --filter TargetHintServiceTests` : 38 tests OK.
- `./scripts/roadie config validate` : status OK, warnings existants hors feature.
- `./scripts/roadie grid show --json` : OK.
- `./scripts/roadie record list` : OK.
