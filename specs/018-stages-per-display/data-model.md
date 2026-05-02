# Data Model — SPEC-018 Stages-per-display

**Status**: Draft
**Last updated**: 2026-05-02

## Vue d'ensemble

Trois familles d'entités :
1. **Clé d'indexation** : `StageScope` (tuple Hashable)
2. **Modèles inchangés** : `Stage`, `StageID`, `StageMember` (cf SPEC-002)
3. **Persistance abstraite** : `StagePersistenceV2` protocol + 2 implémentations (Flat, Nested)
4. **Migration** : `MigrationV1V2` one-shot

## Entités

### `StageScope` (NEW)

Clé Hashable pour indexer les stages par tuple `(display, desktop, stage)`.

```swift
public struct StageScope: Hashable, Sendable, Codable {
    public let displayUUID: String
    public let desktopID: Int
    public let stageID: StageID

    public init(displayUUID: String, desktopID: Int, stageID: StageID) {
        self.displayUUID = displayUUID
        self.desktopID = desktopID
        self.stageID = stageID
    }

    /// Sentinel pour le mode `global` (stages flat sans contexte display/desktop).
    public static func global(_ stageID: StageID) -> StageScope {
        StageScope(displayUUID: "", desktopID: 0, stageID: stageID)
    }

    public var isGlobal: Bool { displayUUID.isEmpty && desktopID == 0 }
}
```

**Invariants** :
- En mode `per_display` : `displayUUID` non vide, `desktopID >= 1`
- En mode `global` : `displayUUID == ""`, `desktopID == 0`, `stageID` valide
- Hashable synthétisé : eq → hash égal (contract Hashable Swift)

### `Stage` (UNCHANGED, SPEC-002)

Réutilise tel quel. Pas de modification du schéma TOML sur disque.

```swift
public struct Stage: Codable, Sendable {
    public let id: StageID
    public var displayName: String
    public var memberWindows: [StageMember]
    public var savedRect: SavedRect?
    // Pas de référence au scope ; le scope est porté par le conteneur
}
```

### `StageManager` (MODIFIED)

```swift
@MainActor
public final class StageManager {
    /// SPEC-018 : indexation par tuple. Remplace l'ancien `[StageID: Stage]`.
    private var stages: [StageScope: Stage] = [:]

    /// Mode courant. Défaut V1 = .global pour compat ascendante.
    public var mode: StageMode = .global

    /// Persistance abstraite. Selon mode :
    /// - .global → FlatStagePersistence
    /// - .perDisplay → NestedStagePersistence
    private var persistence: any StagePersistenceV2

    /// SPEC-018 FR-003 : résolution implicite du scope courant.
    public var currentScope: StageScope { /* via daemon helper */ }

    // Méthodes scopées
    public func stages(in scope: ScopeFilter) -> [Stage]
    public func stage(at scope: StageScope) -> Stage?
    public func createStage(at scope: StageScope, displayName: String) -> Stage
    public func deleteStage(at scope: StageScope)
    public func renameStage(at scope: StageScope, newName: String) -> Bool
    public func switchTo(at scope: StageScope)
    public func assign(wid: WindowID, to scope: StageScope)
}

public enum StageMode: String {
    case global
    case perDisplay = "per_display"
}

/// Filtre pour `stages(in:)` : couvre les cas globaux, par display, par desktop, exact.
public enum ScopeFilter {
    case all                            // (mode global) toutes les stages
    case display(String)                // toutes les stages d'un display
    case displayDesktop(String, Int)    // toutes les stages d'un display+desktop (cas typique)
    case exact(StageScope)              // une stage précise
}
```

**Invariants** :
- En mode `.global` : toutes les clés ont `isGlobal == true`
- En mode `.perDisplay` : toutes les clés ont `isGlobal == false`
- Pas de mélange : un boot = un mode (changement = `daemon reload` requis)

### `StagePersistenceV2` (NEW protocol + 2 impls)

```swift
public protocol StagePersistenceV2: Sendable {
    func loadAll() throws -> [StageScope: Stage]
    func save(_ stage: Stage, at scope: StageScope) throws
    func delete(at scope: StageScope) throws
    func saveActiveStage(_ scope: StageScope?) throws
    func loadActiveStage() throws -> StageScope?
}

/// Mode global : un seul namespace flat, fichiers `<stageID>.toml`.
public final class FlatStagePersistence: StagePersistenceV2 {
    let stagesDir: String
    // Lit/écrit `<stagesDir>/<stageID>.toml`. Toutes les clés retournées sont .global(...).
}

/// Mode per_display : arborescence `<displayUUID>/<desktopID>/<stageID>.toml`.
public final class NestedStagePersistence: StagePersistenceV2 {
    let stagesDir: String
    // Walk le dossier en profondeur 2 + parse les UUIDs et entiers
}
```

### `MigrationV1V2` (NEW)

```swift
@MainActor
public final class MigrationV1V2 {
    public struct Report: Codable {
        public let migratedCount: Int
        public let backupPath: String
        public let targetDisplayUUID: String
        public let durationMs: Int
    }

    public init(stagesDir: String, mainDisplayUUID: String) { ... }

    /// Exécute la migration si applicable. Idempotent.
    /// - Returns : Report si migration faite, nil si déjà faite ou pas applicable
    public func runIfNeeded() throws -> Report?
}
```

**Algorithme** :
1. Si `<stagesDir>.v1.bak/` existe → return nil (déjà fait)
2. Si pas de `<stagesDir>/*.toml` au top-level → return nil (rien à migrer)
3. `cp -r <stagesDir>/ <stagesDir>.v1.bak/`
4. Pour chaque `<id>.toml` au top-level :
   - `mkdir -p <stagesDir>/<mainDisplayUUID>/1/`
   - `mv <id>.toml <stagesDir>/<mainDisplayUUID>/1/<id>.toml`
5. Construire et retourner `Report`

**Erreurs gérées** :
- `MigrationError.diskFull`
- `MigrationError.permissionDenied`
- `MigrationError.partialMigration(count: Int)` — si une partie a réussi, log + flag

## Schéma TOML disque

### Mode global (V1, identique SPEC-002)

```
~/.config/roadies/stages/
├── 1.toml
├── 2.toml
└── 3.toml
```

Contenu `1.toml` :
```toml
display_name = "Default"
[[member_windows]]
cgwid = 12345
bundle_id = "com.googlecode.iterm2"
title_prefix = "iTerm2"
```

### Mode per_display (V2)

```
~/.config/roadies/stages/
├── 37D8832A-2D66-4A47-9B5E-39DA5CF2D85F/  # displayUUID Display 1
│   ├── 1/
│   │   ├── 1.toml
│   │   └── 2.toml
│   └── 2/
│       └── 1.toml
└── 9F22B3D1-8A4E-4B3D-A1F0-2E7C5D9B8A6F/  # displayUUID Display 2
    └── 1/
        ├── 1.toml
        └── 5.toml
```

### Backup V1 (créé une fois au premier boot V2)

```
~/.config/roadies/stages.v1.bak/
├── 1.toml
├── 2.toml
└── 3.toml
```

## IPC envelope

### Réponse étendue de `stage.list`

```json
{
  "status": "success",
  "payload": {
    "current": "1",
    "scope": {
      "display_uuid": "37D8832A-...",
      "display_index": 1,
      "desktop_id": 1,
      "inferred_from": "cursor"
    },
    "mode": "per_display",
    "stages": [
      {
        "id": "1",
        "display_name": "Default",
        "is_active": true,
        "window_ids": [12345, 67890],
        "window_count": 2
      }
    ]
  }
}
```

Champ `inferred_from` : `"cursor"`, `"frontmost"`, `"primary"`, ou `"override"` (si `--display` / `--desktop` passés).

### Args communs étendus

Toutes les commandes `stage.*` (CLI + IPC) acceptent :
```
--display <selector>     # 1..N ou UUID
--desktop <id>           # 1..N
```

Si présents, override la résolution implicite. Si display selector invalide → erreur `unknown_display`. Si desktop hors range → erreur `desktop_out_of_range`.

### Nouvel event `migration_v1_to_v2`

```json
{
  "event": "migration_v1_to_v2",
  "ts": "2026-05-02T19:00:00.000Z",
  "version": 1,
  "migrated_count": 5,
  "backup_path": "/Users/moi/.config/roadies/stages.v1.bak",
  "target_display_uuid": "37D8832A-2D66-4A47-9B5E-39DA5CF2D85F",
  "duration_ms": 23
}
```

### Events `stage_*` enrichis

`stage_changed`, `stage_created`, `stage_renamed`, `stage_deleted` incluent désormais :

```json
{
  "event": "stage_changed",
  "ts": "...",
  "version": 1,
  "from": "1",
  "to": "2",
  "display_uuid": "37D8832A-...",
  "desktop_id": 1
}
```

## Edge cases & invariants

| Edge case | Comportement |
|---|---|
| Curseur hors écran (race au branchement) | Fallback frontmost → primary, jamais d'erreur |
| Display débranché à chaud avec stages actives | Stages préservées sur disque, scope orphelin retourne `display_index = -1` jusqu'au rebranchement |
| Display rebranché (UUID match) | Stages restaurées automatiquement |
| Mode switch global → per_display | Migration runIfNeeded() au prochain boot |
| Mode switch per_display → global | Pas de re-flatten auto ; nested arborescence ignorée mais préservée |
| Création stage avec `--display invalide` | Erreur `unknown_display`, pas de stage créée |
| Création stage avec `--desktop` > range | Erreur `desktop_out_of_range` |
| Backup `stages.v1.bak/` corrompu (préexistant) | Migration skip silencieux ; doc recovery manuelle |

## Persistance / atomicité

- Écriture stage : `tmpfile + rename` atomique (déjà SPEC-002)
- Migration : `cp -r` puis `mv` séquentiel ; en cas de fail à mi-parcours, `stages.v1.bak/` est intact donc recovery manuelle préservée
- Concurrent writes : un seul daemon à la fois (PID-lock SPEC-001)

## Observabilité

- Log structuré JSON-lines `~/.local/state/roadies/daemon.log`
- Events émis : `migration_v1_to_v2` (one-shot), `stage_*` enrichis (continu)
- `daemon.status` expose `stages_mode`, `current_scope`, `migration_pending` pour debug
