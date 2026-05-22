# Plan d'implémentation — SPEC-012 Unification du cycle de vie

## Architecture cible

```
Sources/roadied/main.swift
├── globales (controllers, displaySettlingUntil, pendingDisplayHeal, tilerLiveObserver)
├── fonctions de démarrage UNIQUES (nouvelles)
│   ├── startTilerComponent(interval:ticks:enableLiveEvents:)   ← timer + live observer + display observer
│   ├── startRailComponent()
│   ├── startBorderComponent()
│   ├── startFocusMouseComponent()
│   ├── startTitlebarMenuComponent()
│   ├── startTargetModeComponent()
│   └── startRestoreSafetyComponent()
│
├── case "run"   → appelle les fonctions selon les flags --no-*, puis NSApplication.run()
└── case "tiler"|"rail"|... → runComponent(name) { startXxxComponent() }
```

Une seule définition du démarrage par composant. Les deux modes l'appellent.

## Étapes

### Étape 1 — Extraire les fonctions de démarrage des contrôleurs simples (T001-T004)

Contrôleurs sans logique complexe (rail, border, focus-mouse, titlebar-menu, target-mode, restore-safety) :
- Créer `startRailComponent()`, etc. qui instancient le contrôleur dans la globale et appellent `.start()`.
- Remplacer les corps des sous-commandes `case "rail"` etc. par `runComponent("rail") { startRailComponent() }`.
- Remplacer les blocs `if shouldStartX { ... }` du `case "run"` par `if shouldStartX { startXComponent() }`.

### Étape 2 — Extraire la fonction de démarrage du tiler (T005-T007)

Le plus gros morceau. `startTilerComponent(interval:ticks:enableLiveEvents:)` encapsule :
- `MaintenanceTimerTarget` + `Timer` + `RunLoop.main.add`
- le live observer AX (`AXWindowEventObserver`) retenu dans `tilerLiveObserver`
- l'appel à `installDisplayChangeObserver`

### Étape 3 — Extraire l'observer d'écran (T008)

`installDisplayChangeObserver(displaySettleSeconds:)` encapsule le `NotificationCenter.addObserver` + le heal différé. Appelé par `startTilerComponent`.

### Étape 4 — Réécrire les deux call sites (T009-T010)

- `case "run"` : suite d'appels conditionnés par les flags, dans l'ordre historique, puis `NSApplication.shared.run()`.
- Sous-commandes : `runComponent(name) { startXxx() }`.

### Étape 5 — Validation non-régression (T011-T013)

- `swift build` + `swift test` (428+).
- Smoke monolithique : `roadied run --yes --ticks 1` (ou inspection) → composants attendus.
- Smoke modulaire : `Scripts/start-modular` + `roadie query components` (7) + events `live_tick` / `display-change-heal`.

## Considérations constitutionnelles

| Article | Application |
|---|---|
| III — SpecKit | Cette spec ✓ |
| IV — Disjoncteur | Refactor par petites étapes testées, max 3 tentatives par blocage |
| V — Scope | Refactor pur, aucune nouvelle feature (non-objectif explicite) |
| XV — Test-Before-Next | `swift build` + tests après chaque étape avant commit |
| XVIII — Complexité | Aucune boucle hot path nouvelle ; déplacement de code à complexité égale |

## Critères de PR ready

- [ ] `swift build` OK (PATH Xcode)
- [ ] `swift test` 428+ passants
- [ ] 0 bloc de setup dupliqué (grep des instanciations de contrôleurs : une seule par composant)
- [ ] `roadie query components` inchangé après `Scripts/start-modular`
- [ ] `live_tick` + `display-change-heal` présents dans les deux modes
- [ ] `roadied run --yes` démarre les mêmes composants qu'avant
