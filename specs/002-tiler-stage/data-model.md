# Data Model — SPEC-002 Tiler + Stage Manager

**Feature** : 002-tiler-stage | **Phase** : 1 | **Date** : 2026-05-01

---

## Vue d'ensemble

Quatre couches d'objets, du système physique vers la persistance :

```
[macOS AXUIElement / NSRunningApplication]
          ↓
   [WindowState]   ← snapshot canonique côté daemon
          ↓
   [TreeNode]      ← organisation logique (arbre N-aire)
          ↓
   [Workspace]     ← racine arbre + métadonnées
          ↓
   [Stage]         ← groupe nommé persisté sur disque
```

---

## 1. WindowState

Source de vérité pour toute fenêtre tilée ou flottante. Détient une référence forte à l'`AXUIElement` (durée de vie liée à la fenêtre macOS).

```swift
struct WindowState {
    let cgWindowID: CGWindowID         // clé primaire stable
    let pid: pid_t                     // app process
    let bundleID: String               // ex. com.apple.Terminal
    var title: String                  // varie dans le temps
    var frame: CGRect                  // position+taille AX courante
    let subrole: AXSubrole             // standard / dialog / sheet / system_dialog
    var isFloating: Bool               // true si subrole != standard ou exclu config
    var isMinimized: Bool              // observé via kAXMinimizedAttribute
    var isFullscreen: Bool             // observé via kAXFullScreenAttribute
    var workspaceID: WorkspaceID       // V1 = toujours singleton
    var stageID: StageID?              // nil si stage manager off ou unassigned
    let axElement: AXUIElement         // référence opaque pour AX calls
}

enum AXSubrole: String {
    case standard
    case dialog
    case sheet
    case systemDialog
    case unknown
}
```

**Invariants** :
- `cgWindowID > 0`
- `pid > 0`
- Si `subrole != .standard` → `isFloating = true`
- Si `isFullscreen = true` ou `isMinimized = true` → exclu du calcul de tiling
- `stageID` est nil ou contient un StageID dont le `Stage` existe dans la config

**Cycle de vie** :
1. Création AX (kAXWindowCreatedNotification ou snapshot startup) → `WindowState` créé, ajouté à `WindowRegistry`, le tiler est notifié pour insertion arbre.
2. Mouvements/resize externes → `frame` mise à jour mais le tiler peut "re-asserter" la frame voulue (pour empêcher l'utilisateur de casser le layout).
3. Destruction (kAXUIElementDestroyedNotification) → retiré du registry, du tiler et du stage si applicable.

---

## 2. TreeNode (arbre N-aire)

Structure récursive qui modélise le layout. Inspirée AeroSpace.

```swift
class TreeNode {
    weak var parent: TreeNode?
    var adaptiveWeight: CGFloat        // ratio par rapport aux frères, somme normalisée
    var lastFrame: CGRect?             // mémoïsation pour l'invalidation incrémentale
}

class TilingContainer: TreeNode {
    var children: [TreeNode] = []
    var orientation: Orientation       // .horizontal | .vertical
}

class WindowLeaf: TreeNode {
    let windowID: CGWindowID           // référence WindowState par ID
}

enum Orientation {
    case horizontal
    case vertical

    var opposite: Orientation { self == .horizontal ? .vertical : .horizontal }
}
```

**Règles** :
- L'arbre est invariablement enraciné par un `TilingContainer` (jamais une feuille isolée).
- Une `TilingContainer` avec 0 enfants est invalide → supprimée par garbage collection.
- Une `TilingContainer` avec 1 enfant peut être collapse (l'enfant remplace le container) — normalisation auto.
- `adaptiveWeight` par défaut = 1.0 ; les ratios sont calculés `weight_i / Σ weights` à chaque layout.
- L'arbre N-aire admet plus de 2 enfants par container (différence avec yabai BSP binaire).

**Operations principales** :
- `insert(leaf, after: targetLeaf)` — insère après une feuille référencée. Si `targetLeaf` est seul dans son container, la stratégie de tiling décide (BSP : split ; Master-Stack : ajout en pile).
- `remove(leaf)` — retire et trigger la normalisation du parent.
- `move(leaf, direction)` — déplace dans l'arbre selon la direction (peut traverser plusieurs niveaux).
- `resize(leaf, direction, delta)` — ajuste les `adaptiveWeight` des frères.

---

## 3. Workspace

```swift
struct WorkspaceID: Hashable { let value: String }   // V1 = "main"

struct Workspace {
    let id: WorkspaceID
    var displayID: CGDirectDisplayID                // V1 = main display
    var rootNode: TilingContainer                    // racine arbre tiling
    var tilerStrategy: TilerStrategy                 // BSP par défaut
    var focusedWindowID: CGWindowID?                 // pour insertion / focus commands
    var floatingWindowIDs: Set<CGWindowID>           // hors arbre, jamais tilées
}

enum TilerStrategy: String, Codable {
    case bsp
    case masterStack
    // futurs : .accordion, .fibonacci, etc.
}
```

V1 : un seul Workspace `id = "main"` dans tout le daemon. La structure permet l'extension multi-monitor en V2 sans changer le modèle.

---

## 4. Stage

Persisté sur disque. Lu au démarrage du daemon, écrit après chaque modification (assign, switch).

```swift
struct StageID: Hashable, Codable { let value: String }   // ex. "dev"

struct Stage: Codable {
    let id: StageID
    var displayName: String                          // libellé humain (peut différer de id)
    var memberWindows: [StageMember]                 // ordre = ordre d'assignation
    var tilerStrategy: TilerStrategy                 // chaque stage peut avoir le sien
    var lastActiveAt: Date                           // pour MRU display dans `roadie stage list`
}

struct StageMember: Codable {
    let cgWindowID: CGWindowID                       // peut devenir stale
    let bundleID: String                             // pour re-matcher au redémarrage
    let titleHint: String                            // best-effort matching
    var savedFrame: CGRect?                          // dernière frame avant masquage
}
```

**Persistance** :
- Fichier par stage : `~/.config/roadies/stages/<stageID>.toml`
- Format TOML lisible (pas JSON pour cohérence avec config principale)
- Écriture atomique (`String.write(atomically: true)`)
- Le fichier `~/.config/roadies/stages/active.toml` contient `current_stage = "dev"` (ou absent si stages désactivés)

**Garbage collection au démarrage** :
1. Lire tous les `<stageID>.toml`.
2. Pour chaque `StageMember`, vérifier si le `cgWindowID` existe encore via `CGWindowListCopyWindowInfo`.
3. Si non, tenter un re-match par `(bundleID, titleHint)`. Si succès, mettre à jour le `cgWindowID`.
4. Si échec, retirer le membre du stage avec log explicite.

---

## 5. Command et Response (protocole socket)

Voir `contracts/cli-protocol.md` pour le détail. Résumé :

```swift
enum Command: Codable {
    case windowsList
    case daemonStatus
    case daemonReload
    case focus(direction: Direction)
    case move(direction: Direction)
    case resize(direction: Direction, delta: CGFloat)
    case tilerSet(strategy: TilerStrategy)
    case stageList
    case stageSwitch(stageID: StageID)
    case stageAssign(stageID: StageID)         // assigne la frontmost
    case stageCreate(stageID: StageID, displayName: String)
    case stageDelete(stageID: StageID)
}

enum Response: Codable {
    case success(payload: ResponsePayload)
    case error(code: ErrorCode, message: String)
}

enum Direction: String, Codable { case left, right, up, down }

enum ErrorCode: String, Codable {
    case daemonNotRunning, invalidArgument, unknownStage, stageManagerDisabled,
         windowNotFound, accessibilityDenied, internalError
}
```

---

## 6. Configuration (TOML)

```toml
# ~/.config/roadies/roadies.toml

[daemon]
log_level = "info"   # debug | info | warn | error
socket_path = "~/.roadies/daemon.sock"

[tiling]
default_strategy = "bsp"   # bsp | masterStack
gaps_outer = 8
gaps_inner = 4
master_ratio = 0.6   # pour Master-Stack

[stage_manager]
enabled = false           # FR-013 : opt-in
hide_strategy = "corner"  # corner | minimize | hybrid
default_stage = "main"

[stage_manager.workspaces]
[[stage_manager.workspaces.list]]
id = "dev"
display_name = "Development"

[[stage_manager.workspaces.list]]
id = "comm"
display_name = "Communication"

[exclusions]
# Bundle IDs jamais tilés (toujours flottants)
floating_bundles = [
    "com.apple.systempreferences",
    "com.1password.1password",
]
```

---

## 7. Diagramme de transitions WindowState

```
            kAXWindowCreatedNotification
                       │
                       ▼
                ┌──────────────┐
                │   created    │
                └──────┬───────┘
                       │ subrole == standard ?
              ┌────────┴────────┐
            yes                 no
              ▼                  ▼
        ┌─────────┐         ┌──────────┐
        │  tiled  │ ◄───┐   │ floating │
        └────┬────┘     │   └────┬─────┘
             │          │        │
             │ minimize │        │ minimize
             ▼          │        ▼
        ┌──────────┐    │   ┌──────────┐
        │minimized │────┘   │minimized │
        └────┬─────┘        └────┬─────┘
             │                   │
             │ destroyed         │ destroyed
             ▼                   ▼
        ┌─────────────────────────┐
        │       removed           │
        └─────────────────────────┘
```

Cas spéciaux :
- `fullscreen` : transition `tiled → exclude → tiled` (réintégration au sortie de fullscreen).
- `stage hide` : transition `tiled → moved off-screen` (frame_hidden) sans changement de logique tile.
- `stage show` : restauration de `savedFrame`.

---

## 8. Persistance résumée

| Fichier | Format | Lecture | Écriture |
|---|---|---|---|
| `~/.config/roadies/roadies.toml` | TOML | daemon startup + reload | utilisateur |
| `~/.config/roadies/stages/<id>.toml` | TOML | daemon startup + reload | daemon (atomic) |
| `~/.config/roadies/stages/active.toml` | TOML | daemon startup | daemon (atomic) |
| `~/.local/state/roadies/daemon.log` | JSON-lines | optionnel CLI `roadie logs` | daemon (rotation) |
| `~/.roadies/daemon.sock` | Unix socket | CLI | daemon |
| `~/.roadies/daemon.pid` | PID brut | CLI | daemon |

---

## 9. Notes d'implémentation

- `WindowState` est une struct (valeur) mais contient une `AXUIElement` qui est CFTypeRef (référence partagée). Pas de duplication réelle de l'élément AX.
- L'arbre `TreeNode` utilise des `class` parce que l'identité du nœud importe (parent référencé, comparaisons par `===`).
- `weak var parent` évite les cycles.
- Toutes les opérations sur `Workspace` doivent être faites sur `@MainActor` pour éviter les races avec les events AX.
- Le mapping `(WindowID → AXUIElement)` est tenu par `WindowRegistry` ; le reste du code travaille avec des IDs.
