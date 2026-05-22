# Research — Unification du cycle de vie des composants

## État actuel (constaté dans Sources/roadied/main.swift)

Duplication identifiée :
- **Tiler** : le bloc de setup (MaintenanceTimerTarget + Timer + live observer AX) existe en double : lignes ~162-237 dans `case "run"` ET lignes ~248-343 dans `case "tiler"` via `runComponent`.
- **displayChangeObserver** : présent dans `run` (141-160) et dupliqué dans `tiler`.
- **Contrôleurs UI** (`RailController`, `BorderController`, `FocusFollowsMouseController`, `TitlebarContextMenuController`, `TargetModeRuntimeController`, `RestoreSafetyRuntimeController`) : instanciés dans `run` (conditionnés par `--no-*`) ET dans leur sous-commande respective.

Conséquence : 4 bugs du 2026-05-22 (observer d'écran manquant côté modulaire, live observer manquant, events dupliqués) venaient d'un setup présent dans `run` mais oublié dans la sous-commande.

## Décisions techniques

### D1 — Fonctions de démarrage top-level dans main.swift

Les fonctions de démarrage manipulent :
- des variables globales top-level (`railController`, `displaySettlingUntil`, `pendingDisplayHeal`, `tilerLiveObserver`, etc.)
- `NSApplication.shared` et `RunLoop.main`
- les arguments CLI (`value(after:)`, `args`)

Ces dépendances sont propres à l'exécutable `roadied`, pas réutilisables ailleurs. Donc on garde les fonctions **dans `main.swift`** (top-level), pas dans un module `RoadieDaemon`. C'est le scope minimal (constitution : pas d'abstraction au-delà du besoin).

Signatures envisagées :
```swift
func startTilerComponent(interval: Double, ticks: Int?, enableLiveEvents: Bool)
func startRailComponent()
func startBorderComponent()
func startFocusMouseComponent()
func startTitlebarMenuComponent()
func startTargetModeComponent()
func startRestoreSafetyComponent()
func installDisplayChangeObserver(displaySettleSeconds: Double)
```

### D2 — Le tiler porte sa propre installation d'observer d'écran

Aujourd'hui `installDisplayChangeObserver` est appelé dans `run` indépendamment du tiler, mais le heal qu'il déclenche n'a de sens que si un writer (tiler) tourne. Décision : `startTilerComponent` installe lui-même l'observer d'écran. En monolithique, si `--no-tiler`, pas d'observer d'écran (cohérent : sans tiler, pas de re-layout au changement d'écran). Cela simplifie et garantit la parité.

### D3 — Run loop : inchangé

- `case "run"` : appelle les fonctions de démarrage selon flags, puis `NSApplication.shared.run()` une seule fois à la fin.
- Sous-commandes : `runComponent(name) { startXxxComponent() }` — `runComponent` gère déjà le lock PID + signaux + `NSApplication.shared.run()`.

Les composants qui utilisent `RunLoop.main.add(timer)` fonctionnent sous `NSApplication.run()` (qui fait tourner le run loop principal). Pas de changement nécessaire.

### D4 — Variables d'état partagées

`displaySettlingUntil` et `pendingDisplayHeal` restent globales top-level (lues par le `shouldTick` du tiler ET écrites par l'observer d'écran). Le live observer retient ses closures via `tilerLiveObserver` (déjà globale). Pas de changement de modèle de concurrence.

### D5 — Préservation stricte du comportement

Le refactor est un **déplacement de code** (extract function), pas une réécriture. Chaque ligne déplacée doit produire le même effet. Validation : la suite de tests + comparaison `roadie query components` + events `live_tick`/`display-change-heal` dans les deux modes.

## Risques

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Capture de variable cassée en déplaçant les closures | Moyenne | Élevé | Garder les globales top-level ; tester live_tick dans les 2 modes |
| Ordre de démarrage des composants modifié | Faible | Moyen | Préserver l'ordre exact (restore-safety, rail, border, focus, titlebar, target, puis tiler) |
| Régression run loop (timer non ajouté) | Faible | Élevé | Test smoke : le tiler émet des layout_apply après refactor |
| `--no-tiler` ne désactive plus l'observer d'écran | Moyenne | Faible | D2 documente le nouveau comportement (acceptable) |

## Pas de recherche externe nécessaire

Refactor interne sans nouvelle dépendance ni pattern IA/sécurité. Article IX (recherche préalable) non applicable.
