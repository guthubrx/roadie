# Phase 1 — Data Model : Roadie Virtual Desktops

**Spec** : SPEC-011 | **Date** : 2026-05-02

## Entités principales

### RoadieDesktop

Représente un desktop virtuel roadie. Stockage : `~/.config/roadies/desktops/<id>/state.toml`.

| Champ | Type | Description | Validation |
|---|---|---|---|
| `id` | `Int` | Identifiant unique | 1 ≤ id ≤ 16 |
| `label` | `String?` | Nom optionnel | ≤ 32 chars, regex `^[a-zA-Z0-9_-]+$` ou `nil` |
| `layout` | `Layout` | Stratégie de tiling | `bsp` \| `master_stack` \| `floating` |
| `gapsOuter` | `Int` | Marge extérieure pixels | 0 ≤ gaps ≤ 100 |
| `gapsInner` | `Int` | Espacement entre fenêtres | 0 ≤ gaps ≤ 100 |
| `activeStageID` | `Int` | Stage actuellement focusé | 1 ≤ activeStageID ≤ count(stages) |
| `stages` | `[Stage]` | Stages du desktop | ≥ 1 (toujours au moins un stage par défaut) |
| `windows` | `[Window]` | Fenêtres assignées au desktop | indexées par `cgwid` |

**Invariants** :
- `activeStageID` doit référencer un stage dans `stages`.
- Chaque `Window.stageID` dans `windows` doit référencer un stage existant.
- Pas de doublon de `cgwid` dans `windows`.

**Source de vérité** : fichier disque (`state.toml`), copie en mémoire dans `DesktopRegistry`. Écriture disque atomique (write-then-rename).

---

### Window

Représente une fenêtre macOS suivie par roadie. Étend le `WindowState` existant de `RoadieCore`.

| Champ | Type | Description | Validation |
|---|---|---|---|
| `cgwid` | `CGWindowID` (UInt32) | Identifiant macOS stable | non-zéro |
| `bundleID` | `String` | Bundle ID de l'app | non-vide |
| `title` | `String` | Titre courant (info) | peut être vide |
| `expectedFrame` | `CGRect` | Position/taille attendues quand on-screen | origin.x ≥ 0 ou cas migration depuis offscreen |
| `desktopID` | `Int` | Desktop d'appartenance | référence valide |
| `stageID` | `Int` | Stage local au desktop | référence valide |

**Source de vérité** : `WindowRegistry` (RoadieCore) pour la liste live. Le `desktopID` est ajouté par cette spec.

**Mise à jour de `expectedFrame`** :
- Observée par AX (`kAXPositionChangedNotification`, `kAXSizeChangedNotification`).
- Mise à jour **uniquement** si `desktopID == currentDesktopID` (sinon on capturerait la position offscreen).
- Persistée à chaque modification ou à chaque bascule.

---

### Stage

Sous-groupe de fenêtres dans un desktop. Sémantique préservée de SPEC-001.

| Champ | Type | Description | Validation |
|---|---|---|---|
| `id` | `Int` | Identifiant local au desktop | 1..M, M ≤ 9 (limite UI raccourcis ⌥+1..9) |
| `label` | `String?` | Nom optionnel | ≤ 32 chars, regex alphanum |
| `windows` | `[CGWindowID]` | CGWIDs des fenêtres assignées | sous-ensemble des `windows` du desktop parent |

**Invariant** : `Set(stage.windows for stage in desktop.stages) == Set(desktop.windows.cgwid)` — toute fenêtre du desktop appartient à exactement un stage (pas de dangling).

---

### Event (canal observable)

Émis par le `EventBus` à chaque transition.

| Champ | Type | Valeurs |
|---|---|---|
| `event` | `String` | `"desktop_changed"` \| `"stage_changed"` |
| `from` | `String` | id source (`"1"`, `"2"`, ou label) |
| `to` | `String` | id cible |
| `ts` | `Int64` | Unix epoch millisecondes |

Sérialisation JSON-lines, une ligne par event.

---

### DesktopRegistry (state in-memory)

Acteur (Swift `actor`) qui détient :

| Champ | Type | Description |
|---|---|---|
| `desktops` | `[Int: RoadieDesktop]` | Dict id → RoadieDesktop |
| `currentID` | `Int` | Desktop courant |
| `recentID` | `Int?` | Desktop précédemment courant (pour back-and-forth) |
| `count` | `Int` | Nombre de desktops actifs (de la config) |

Méthodes publiques :
- `load(from configDir: URL)` — charge tous les desktops depuis disque
- `save(_ desktop: RoadieDesktop)` — persiste un desktop
- `desktop(id:) -> RoadieDesktop?` — accès direct
- `setCurrent(id:)` — met à jour `currentID`/`recentID`
- `windows(of desktopID:) -> [Window]` — fenêtres d'un desktop
- `assignWindow(cgwid:to:stage:)` — modifie l'appartenance

---

### DesktopSwitcher (logique métier)

Acteur Swift qui orchestre la bascule. Détient une référence au `DesktopRegistry`, au `WindowRegistry` (RoadieCore), et au hook `setLeafVisible` ou équivalent move-window.

État interne :

| Champ | Type | Description |
|---|---|---|
| `pendingTarget` | `Int?` | Desktop demandé en dernier mais pas encore appliqué (collapse) |
| `inFlight` | `Bool` | Bascule en cours |

Méthodes :
- `switch(to id: Int) async throws` — bascule (sérialisée)
- `back() async throws` — bascule vers `recentID`

**State machine de `switch(to:)`** :

```
État initial : inFlight = false, pendingTarget = nil

switch(to: N) :
  IF inFlight :
    pendingTarget = N
    return (la bascule courante terminera puis appliquera N)
  ELSE :
    inFlight = true
    DO :
      hide(windows of currentID)
      show(windows of N)
      registry.setCurrent(id: N)
      bus.publish(desktop_changed)
    next = pendingTarget
    pendingTarget = nil
    inFlight = false
    IF next != nil ET next != currentID :
      switch(to: next!) recurse
```

---

## Transitions d'état

### Bascule normale (FR-002)

```
[currentID = A]
    │
    ▼ switch(to: B)
[hiding A windows]   ← move offscreen via AX
    │
    ▼
[restoring B windows] ← move back to expectedFrame
    │
    ▼
[applying B layout]   ← appel tiler
    │
    ▼
[currentID = B, recentID = A, event emitted]
```

### Bascule no-op (FR-006)

```
[currentID = A]
    │
    ▼ switch(to: A) sans back_and_forth
[no-op : aucune action]
    │
    ▼
[currentID = A, aucun event]
```

### Bascule back-and-forth (FR-006 + back_and_forth=true)

```
[currentID = A, recentID = C]
    │
    ▼ switch(to: A) avec back_and_forth=true
[équivalent à switch(to: C)]
    │
    ▼
[currentID = C, recentID = A]
```

### Migration V1 → V2 (FR-021)

```
[~/.config/roadies/desktops/ vide ou inexistant]
[~/.config/roadies/stages/N pour N in 1..M]
    │
    ▼ daemon boot
[lire stages V1]
    │
    ▼
[créer ~/.config/roadies/desktops/1/state.toml]
[avec stages = [stage 1, ..., stage M] de V1]
[avec windows = union des fenêtres V1]
    │
    ▼
[currentID = 1, recentID = nil]
```

### Migration SPEC-003 archive (FR-022, R-006)

```
[~/.config/roadies/desktops/<UUID>/ existe (format SPEC-003)]
    │
    ▼ daemon boot
[rename ~/.config/roadies/desktops/<UUID>/ → ~/.config/roadies/desktops/.archived-spec003-<UUID>/]
[log warning unique]
    │
    ▼
[procéder migration V1 → V2 normale]
```

---

## Validation des contraintes

| Contrainte spec | Vérifié par |
|---|---|
| FR-001 (count 1..16) | `Config.parse()` valide la valeur |
| FR-005 (expectedFrame mise à jour on-screen seulement) | `WindowRegistry` filtre par `desktopID == currentID` |
| FR-006 (idempotence) | `DesktopSwitcher.switch` early-return |
| FR-008 (stages indépendants) | `StageManager` filtre par `desktopID` |
| FR-011 (persistance immédiate) | `DesktopRegistry.save()` appelée après chaque mutation |
| FR-013 (corruption recovery) | `try? load()` avec init vierge en fallback |
| FR-023 (range check) | `DesktopSwitcher.switch` valide `1..count` |
| FR-024 (fenêtre disparue) | `WindowRegistry.lookup(cgwid)` retourne nil → skip |
| FR-025 (concurrence) | `actor DesktopSwitcher` + `pendingTarget` |

---

## Format disque exemple complet

```toml
# ~/.config/roadies/desktops/2/state.toml
id = 2
label = "comm"
layout = "bsp"
gaps_outer = 8
gaps_inner = 4
active_stage_id = 1

[[stages]]
id = 1
label = "main"
windows = [12345, 67890]

[[stages]]
id = 2
label = "extras"
windows = [13579]

[[windows]]
cgwid = 12345
bundle_id = "com.tinyspeck.slackmacgap"
title = "Slack"
expected_x = 100.0
expected_y = 100.0
expected_w = 1200.0
expected_h = 800.0
stage_id = 1

[[windows]]
cgwid = 67890
bundle_id = "com.apple.mail"
title = "Inbox"
expected_x = 1320.0
expected_y = 100.0
expected_w = 600.0
expected_h = 800.0
stage_id = 1

[[windows]]
cgwid = 13579
bundle_id = "com.apple.Safari"
title = "Apple"
expected_x = 200.0
expected_y = 200.0
expected_w = 1400.0
expected_h = 900.0
stage_id = 2
```
