# Data Model — Multi-desktop awareness (SPEC-003)

**Date** : 2026-05-01

## Entités

### `Desktop`

Représentation roadie d'un desktop macOS observé.

| Champ | Type | Source | Description |
|---|---|---|---|
| `uuid` | String | SkyLight `CGSCopyManagedDisplaySpaces` | Identifiant stable entre redémarrages |
| `index` | Int | Position dans le tableau | Volatile, change au réordonnancement utilisateur |
| `label` | String? | Saisi via `roadie desktop label` | Facultatif, persisté dans le state |
| `lastActiveAt` | Date | Mis à jour à chaque switch in | Pour la commande `desktop focus recent` |

### `DesktopState` (persisté `~/.config/roadies/desktops/<uuid>.toml`)

État complet d'un desktop, indépendant des autres.

| Champ | Type | Description |
|---|---|---|
| `desktopUUID` | String | Clé primaire = nom du fichier |
| `displayName` | String? | Label utilisateur facultatif |
| `stages` | `[Stage]` | Liste des stages (réutilise type V1 `RoadieStagePlugin.Stage`) |
| `currentStageID` | StageID? | Stage actif au moment du switch out |
| `rootNode` | TreeNode | Arbre BSP propre à ce desktop (sérialisé via le mécanisme de SPEC-002) |
| `tilerStrategy` | TilerStrategy | Stratégie active sur ce desktop (peut différer du défaut global) |
| `gapsOverride` | OuterGaps? | Si non nil, override les gaps globaux (cf. T102 SPEC-002) |
| `version` | Int | Schema version pour migrations futures (V2 = 1) |

**Validation** :
- `desktopUUID` non vide, format UUID standard
- `stages` peut être vide (desktop fraîchement initialisé)
- `currentStageID` doit référencer un stage existant dans `stages` (ou nil)
- `rootNode` cohérent : feuilles présentes dans le registry des fenêtres de ce desktop uniquement

**State transitions** :
- **Init** : nouveau desktop → `DesktopState(desktopUUID, stages: [], currentStageID: nil, rootNode: empty, tilerStrategy: config.default)`
- **Switch in** : lecture lazy depuis disque → mise en mémoire active
- **Switch out** : sérialisation atomique vers disque (temp + rename)
- **Window event** (création/destruction/focus/move) : mise à jour en mémoire si desktop est actif, sinon ignoré (la fenêtre appartient à un autre desktop)

### `Event`

Message émis sur le canal events.

| Champ | Type | Description |
|---|---|---|
| `eventName` | String | Énum string : `desktop_changed`, `stage_changed`, autres futurs |
| `ts` | ISO8601 | Timestamp UTC précision millisec |
| `payload` | `[String: AnyCodable]` | Champs spécifiques à l'event |

**Events V2 minimums** :

```jsonc
// desktop_changed
{
  "event": "desktop_changed",
  "ts": "2026-05-01T13:42:51.832Z",
  "from": "uuid-A",        // null si premier boot
  "to": "uuid-B",
  "from_index": 1,
  "to_index": 2
}

// stage_changed
{
  "event": "stage_changed",
  "ts": "2026-05-01T13:43:00.123Z",
  "desktop_uuid": "uuid-B",
  "from": "stage1",        // null si désactivation
  "to": "stage2"
}
```

### `WindowState` (extension du modèle V1)

Ajout d'un champ pour rattacher une fenêtre à son desktop.

| Champ ajouté | Type | Description |
|---|---|---|
| `desktopUUID` | String? | UUID du desktop sur lequel la fenêtre est physiquement présente. Mise à jour au boot et à chaque transition de desktop. `nil` si pas encore résolu. |

Tous les autres champs V1 (`cgWindowID`, `pid`, `bundleID`, `title`, `frame`, `subrole`, `isFloating`, `isMinimized`, `stageID`) restent inchangés.

### `DesktopRule` (config statique, optionnelle)

Section `[[desktops]]` répétable dans `roadies.toml`.

| Champ | Type | Description |
|---|---|---|
| `match_index` | Int? | Match par index Mission Control (mutuellement exclusif avec `match_label`) |
| `match_label` | String? | Match par label utilisateur |
| `default_strategy` | TilerStrategy? | Override de la stratégie de tiling pour ce desktop |
| `gaps_outer` | Int? | Override marge uniforme |
| `gaps_outer_top/bottom/left/right` | Int? | Override par côté |
| `gaps_inner` | Int? | Override marge inter-fenêtres |
| `default_stage` | String? | ID du stage par défaut à activer au premier accès |

**Validation** :
- Au moins un de `match_index` ou `match_label` non nil
- Pas les deux en même temps
- Tous les autres champs purement optionnels

---

## Diagramme relations

```text
                         ┌───────────────────┐
                         │   Desktop (RAM)   │
                         │   uuid, index,    │
                         │   label, active   │
                         └─────────┬─────────┘
                                   │ 1 ↔ 1
                                   ▼
                         ┌─────────────────────────┐
                         │   DesktopState (disk)   │
                         │   ~/.config/roadies/    │
                         │   desktops/<uuid>.toml  │
                         └────┬────────────────────┘
                              │ 1 ↔ N
                              ▼
                         ┌──────────────┐
                         │    Stage     │
                         │   (V1 type)  │
                         └──────┬───────┘
                                │ 1 ↔ N
                                ▼
                         ┌──────────────┐
                         │  WindowState │
                         │  + desktopUUID│
                         └──────────────┘

   Config          Runtime
  ┌──────────────┐    │
  │ DesktopRule  │────┘ override default_strategy / gaps / default_stage
  │ (in toml)    │
  └──────────────┘
```

---

## Persistance — exemple concret de fichier `~/.config/roadies/desktops/<uuid>.toml`

```toml
desktop_uuid = "550e8400-e29b-41d4-a716-446655440000"
display_name = "code"
tiler_strategy = "bsp"
current_stage_id = "1"
version = 1

[gaps_override]
top = 4
bottom = 30
left = 12
right = 12

[[stages]]
id = "1"
display_name = "Work"
last_active_at = "2026-05-01T13:42:51Z"

[[stages.member_windows]]
cg_window_id = 42
bundle_id = "com.googlecode.iterm2"
title_hint = "iTerm2 — main"
saved_frame = { x = 0, y = 25, w = 1024, h = 1255 }

[[stages]]
id = "2"
display_name = "Personal"
last_active_at = "2026-05-01T12:30:00Z"
member_windows = []

[root_node]
# Sérialisation TreeNode existante de SPEC-002 (réutilisée telle quelle)
```

---

## Compatibilité avec V1

- Les types `Stage`, `StageMember`, `SavedRect`, `TreeNode`, `OuterGaps` de V1 sont **réutilisés intégralement**. Pas de duplication.
- Le seul changement structurel V1→V2 est l'ajout du champ `desktopUUID` sur `WindowState` et la séparation de la persistance en fichiers par desktop.
- En mode `multi_desktop.enabled = false`, le code V1 fonctionne exactement comme avant : un seul fichier d'état partagé, le `desktopUUID` est ignoré.
