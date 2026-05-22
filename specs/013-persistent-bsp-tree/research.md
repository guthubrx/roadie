# Research — Arbre BSP persistant

## Architecture existante (points d'intégration)

- `WindowManagementMode` (enum, RoadieCore) : `bsp | mutableBsp | masterStack | float`. Ajouter un cas.
- `LayoutPlanner.plan(request)` (RoadieTiler) : switch sur `request.mode` → stratégie. Ajouter une branche.
- `LayoutStrategy` protocol : `plan(_ request: LayoutRequest) -> LayoutPlan`.
- `LayoutRequest` : `windowIDs`, `currentFrames`, `priorityWindowIDs`, `newWindowIDs`, `splitPolicy`, `container`, gaps. Les stratégies actuelles dérivent tout de la **liste** + frames.
- `PersistentStage` (StageStore) : contient `members: [PersistentStageMember]`, `mode`, `groups`, focus. C'est ici qu'on persistera l'arbre.
- `DaemonSnapshot.layoutPlan(...)` construit le `LayoutRequest` depuis le snapshot. Point où l'arbre doit être fourni à la stratégie.

## Différence clé avec l'existant

Les stratégies actuelles sont **sans état** : `plan(request)` est une fonction pure de (liste + frames). L'arbre BSP est un **état persistant** : il mémorise la structure (qui a coupé qui). On ne peut pas le dériver de la seule liste.

→ Conséquence : l'arbre doit être (a) stocké par stage, (b) reconcilié avec les fenêtres réelles à chaque tick, (c) passé à la stratégie.

## Décisions techniques

### D1 — Modèle d'arbre (RoadieTiler)

```swift
public indirect enum BSPTree: Equatable, Codable, Sendable {
    case leaf(WindowID)
    case split(orientation: BSPOrientation, ratio: Double, first: BSPTree, second: BSPTree)
    case empty
}
public enum BSPOrientation: String, Codable, Sendable { case horizontal, vertical }
```
- `leaf` = une fenêtre. `split` = nœud interne (ratio = part du `first`). `empty` = stage vide.
- `first` = gauche/haut, `second` = droite/bas.

### D2 — Opérations sur l'arbre (pures, testables)

- `insert(window:nextTo:side:)` : trouve la feuille `nextTo` (focus), la remplace par un split [feuille, nouvelle] selon `side` (right/left → second/first) et orientation (selon ratio du pane).
- `remove(window:)` : retire la feuille, remonte le frère à la place du parent.
- `windowIDs` : feuilles dans l'ordre (gauche→droite, haut→bas).
- `place(in: CGRect, gaps:)` : parcours récursif → `[WindowID: CGRect]`.
- `contains(window:)`, `adoptRatio(...)` (resize manuel).

### D3 — Reconciliation (RoadieDaemon)

À chaque snapshot, comparer les feuilles de l'arbre aux fenêtres réelles du stage :
- fenêtre réelle absente de l'arbre → `insert` à côté du focus (ou racine si arbre vide).
- feuille de l'arbre sans fenêtre réelle → `remove`.
- L'arbre reste la source de **structure** ; les fenêtres réelles sont la source de **présence**.

### D4 — Nouveau mode

Ajouter `WindowManagementMode.spatialBsp` (valeur TOML `spatial_bsp` / `spatial` / `tree`). Activable via `default_strategy = "spatial_bsp"` ou par stage. Les modes existants restent inchangés.

### D5 — Persistance

Ajouter `bspTree: BSPTree?` à `PersistentStage` (Codable, optionnel pour rétro-compat). Migration : si `mode == .spatialBsp` et `bspTree == nil`, construire un arbre initial depuis `members` (split équilibré).

### D6 — Config direction

Étendre `WindowPlacementConfig` avec `newWindowSide: String` (`"right"` | `"left"`, clé TOML `new_window_side`, défaut `"right"`). Propagé jusqu'à `insert(...:side:)`.

### D7 — Orientation du split (yabai-like)

À l'insertion, l'orientation suit la dimension dominante du pane focalisé : largeur ≥ hauteur → split vertical (côte à côte) ; sinon horizontal (empilé).

## Risques

| Risque | Mitigation |
|---|---|
| Corruption arbre vs réalité AX | Reconciliation défensive : la présence des fenêtres prime ; arbre reconstruit si incohérent |
| Interaction parking heal / grace period (SPEC-010/011) | L'arbre n'est touché que pour les fenêtres live du stage actif ; les fenêtres missing gardées hors reconciliation |
| Migration état existant | D5 : arbre construit depuis members si absent |
| Régression autres modes | Nouveau cas isolé dans le switch ; tests existants inchangés |

## Stratégie d'implémentation (2 couches)

1. **Cœur pur (P1, 100% testable sans macOS)** : `BSPTree` + opérations + `SpatialBSPLayoutStrategy` + tests unitaires. C'est la fondation et la partie la plus risquée à valider.
2. **Intégration runtime (P1-P2)** : persistance dans PersistentStage, reconciliation dans DaemonSnapshot, config, branchement LayoutPlanner.

## Pas de recherche externe bloquante

Le BSP à arbre est un pattern documenté (yabai, i3). Implémentation maison, pas de dépendance.
