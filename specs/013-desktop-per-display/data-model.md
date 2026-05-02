# Data Model — SPEC-013 Desktop par Display

**Date** : 2026-05-02 | **Phase** : 1

## Modèle de données runtime

### `DesktopMode` (enum, RoadieCore/Config.swift)

```swift
public enum DesktopMode: String, Codable, Sendable {
    case global       // V2 : un seul current desktop pour tous les écrans
    case perDisplay = "per_display"  // V3 : current par display
}
```

Sourcé depuis `roadies.toml` :

```toml
[desktops]
mode = "per_display"   # ou "global" (défaut)
count = 10
```

**Validation** : si la valeur TOML est inconnue (`"weird"`), parser fallback à `.global` + log warn (FR-002).

---

### `DesktopRegistry` (existant, RoadieDesktops/DesktopRegistry.swift)

Champs ajoutés ou modifiés :

```swift
public actor DesktopRegistry {
    // SUPPRIMÉ : public private(set) var currentID: Int  (remplacé par la map)

    /// Map current desktop par display (FR-004). En mode global, toutes les
    /// entries sont synchronisées. En per_display, indépendantes.
    public private(set) var currentByDisplay: [CGDirectDisplayID: Int] = [:]

    /// Mode runtime, lu depuis Config. Settable à chaud via reload (FR-003).
    public var mode: DesktopMode = .global

    /// Compatibility shim : retourne currentByDisplay du primary (mode global)
    /// ou du display de la frontmost (mode per_display).
    /// Utilisé par tous les call-sites legacy qui demandent "le current desktop".
    public func currentID(for displayID: CGDirectDisplayID? = nil) -> Int {
        if let did = displayID, let v = currentByDisplay[did] { return v }
        // Fallback primary
        let primaryID = CGMainDisplayID()
        return currentByDisplay[primaryID] ?? 1
    }

    /// Mute le current d'un display. En mode global, propage à tous les autres.
    /// En per_display, mute uniquement la cible.
    public func setCurrent(_ desktopID: Int, on displayID: CGDirectDisplayID) {
        switch mode {
        case .global:
            for k in currentByDisplay.keys { currentByDisplay[k] = desktopID }
        case .perDisplay:
            currentByDisplay[displayID] = desktopID
        }
        // Émet event desktop_changed avec display_id (FR-024)
    }
}
```

**Invariants** :
- En mode `global` : `Set(currentByDisplay.values).count <= 1` (tous égaux).
- Pour chaque `displayID` connu de `DisplayRegistry`, `currentByDisplay[displayID]` est défini après le boot (init avec valeur 1 ou valeur restaurée disque).
- Un display retiré → entry retirée de `currentByDisplay` (sa valeur est persistée disque, sera relue au rebranchement).

---

### `WindowState` (existant, RoadieCore/Types.swift)

Aucun changement structurel. Les champs `desktopID: Int` et `expectedFrame: CGRect` existants suffisent. La sémantique évolue : en mode `per_display`, `desktopID` indique le desktop **du display où la fenêtre est physiquement positionnée**. Lors d'un drag cross-display, `desktopID` est mis à jour (FR-011).

---

## Modèle de données persistant

### Arborescence sur disque

```
~/.config/roadies/
├── roadies.toml                          # Config (mode, count, etc)
└── displays/
    ├── 4DAC02A1-9F25-...-A8E4F7B/        # UUID built-in
    │   ├── current.toml                  # current_desktop_id = N
    │   └── desktops/
    │       ├── 1/
    │       │   └── state.toml            # fenêtres assignées au desktop 1 du built-in
    │       ├── 2/
    │       │   └── state.toml
    │       └── ...
    └── 9B7C45F2-...-C3D2E1F4/            # UUID LG HDR 4K
        ├── current.toml
        └── desktops/
            └── 1/
                └── state.toml
```

### Format `current.toml` (par display)

```toml
# ~/.config/roadies/displays/<uuid>/current.toml
current_desktop_id = 2
last_updated = "2026-05-02T13:45:12Z"
```

**Champs** :
- `current_desktop_id: Int` — desktop courant pour cet écran. Range 1..config.desktops.count.
- `last_updated: String` (ISO 8601) — pour debug.

### Format `desktops/<id>/state.toml` (par display × desktop)

```toml
# ~/.config/roadies/displays/<uuid>/desktops/2/state.toml
# Identique au format SPEC-011 — réutilisé tel quel.
[[windows]]
cgwid = 12345
bundle_id = "com.googlecode.iterm2"
title_prefix = "Default ~/.zsh — Mac"
expected_frame = [100.0, 50.0, 1024.0, 768.0]
display_uuid = "4DAC02A1-..."
stage_id = "1"
```

**Migration de SPEC-012 vers SPEC-013** : le champ `display_uuid` existant indique le display d'appartenance au moment de la sauvegarde (utile pour matching FR-018). Pas de breaking change.

---

## Transitions d'état

### `desktop focus N` en mode `per_display`

```
État avant : currentByDisplay = { 1: 1, 4: 1 }, mode = per_display
                                  ↑ built-in   ↑ LG
              frontmost = wid sur display 4 (LG)

Action : roadie desktop focus 2

État après : currentByDisplay = { 1: 1, 4: 2 }
              fenêtres LG dont desktopID=1 → cachées (offscreen)
              fenêtres LG dont desktopID=2 → restaurées à expectedFrame
              fenêtres built-in → INCHANGÉES
              persistance : displays/<lgUUID>/current.toml mis à jour
              event desktop_changed { from: 1, to: 2, display_id: 4 } émis
```

### Drag cross-display en mode `per_display`

```
État avant : currentByDisplay = { 1: 1, 4: 3 }, mode = per_display
              wid F a desktopID=1, frame sur display 1 (built-in)

Action : utilisateur drag F vers le LG (display 4)

Détection : onDragDrop calcule realDisplayID=4 vs treeDisplayID=1 → migration cross-display
État après : F.desktopID = currentByDisplay[4] = 3 (FR-011)
              F.frame ajustée à la nouvelle position drop sur LG
              F est insérée dans l'arbre BSP du LG (logique SPEC-012)
              persistance : displays/<lgUUID>/desktops/3/state.toml mis à jour avec F
                            displays/<bUUID>/desktops/1/state.toml mis à jour (F retirée)
```

### Débranchement écran

```
État avant : displays = [built-in, LG]
              currentByDisplay = { 1: 2, 4: 3 }
              fenêtres LG = [F1, F2, F3] desktopID=3

Action : utilisateur débranche LG

Détection : didChangeScreenParameters → handleDisplayConfigurationChange (SPEC-012)
État après :
  - displays = [built-in]
  - currentByDisplay = { 1: 2 }   (entry 4 retirée RUNTIME)
  - F1/F2/F3 migrées sur built-in (frames clampées au visibleFrame built-in)
  - F1/F2/F3 ont leur desktopID inchangé (FR : ils gardent 3, donc cachées sur built-in
    qui est sur desktop 2 — UX cohérente avec yabai/aerospace)
  - displays/<lgUUID>/desktops/3/state.toml CONSERVÉ INTACT sur disque (FR-019)
  - displays/<lgUUID>/current.toml CONSERVÉ INTACT
  - Event display_configuration_changed émis
```

### Rebranchement écran

```
État avant : displays = [built-in]
              currentByDisplay = { 1: 2 }
              F1/F2/F3 sur built-in (migrées au débranchement)
              displays/<lgUUID>/ existe sur disque (intact)

Action : utilisateur rebranche LG

Détection : didChangeScreenParameters → nouvel écran ID=4 ressuscite
État après :
  - displays = [built-in, LG]
  - Lecture displays/<lgUUID>/current.toml → currentByDisplay[4] = 3 (restauré)
  - Lecture displays/<lgUUID>/desktops/3/state.toml → liste F1, F2, F3 + frames
  - Pour chaque F dans la liste :
      * Niveau 1 matching : F encore dans WindowRegistry par cgwid ? → restore frame.
      * Niveau 2 matching : sinon, chercher par bundleID + title prefix.
      * Aucun match → ignore silencieusement (FR-020).
  - F1/F2/F3 retournent visuellement sur le LG à leur expectedFrame d'origine.
  - Event display_configuration_changed émis avec display_id=4.
```

### Switch de mode à chaud

```
Cas A — global → per_display :
  - currentByDisplay = { 1: 2, 4: 2 } (étaient égaux)
  - mode passe à per_display
  - currentByDisplay reste { 1: 2, 4: 2 } (chacun garde sa valeur, qui est la même)
  - À partir de maintenant, les mutations sont indépendantes par display.

Cas B — per_display → global :
  - currentByDisplay = { 1: 1, 4: 3 } (divergent)
  - mode passe à global
  - On synchronise tous sur la valeur du primary : { 1: 1, 4: 1 }
  - LG bascule visuellement de desktop 3 vers 1 (cache F.desktop=3, montre F.desktop=1).
```

---

## Validation rules

| Règle | Quand | Action si violée |
|---|---|---|
| `mode` ∈ {"global", "per_display"} | Parsing TOML | Fallback "global" + log warn (FR-002) |
| `current_desktop_id` ∈ [1, config.desktops.count] | Lecture current.toml au boot | Fallback à 1 + log warn |
| `state.toml.windows[i].cgwid` valide UInt32 | Lecture state.toml | Skip cette entry, continue les autres |
| `display_uuid` parsable | Lecture state.toml | Si UUID invalide, skip restore pour cette entry |
| Cohérence mode global : `Set(currentByDisplay.values).count <= 1` | Après chaque mutation en mode global | Log assert error (devrait être impossible si setCurrent respecte FR-005) |

---

## Conformité avec spec FRs

| FR | Adressé par |
|---|---|
| FR-001 (mode dans TOML) | `Config.swift` extension `DesktopsConfig.mode` |
| FR-002 (fallback global si invalide) | Parser TOML avec catch + warn |
| FR-003 (reload à chaud) | `daemon reload` re-lit config + appelle `DesktopRegistry.setMode` |
| FR-004 (currentByDisplay map) | `DesktopRegistry.currentByDisplay` |
| FR-005, FR-006 (sync vs indep) | `DesktopRegistry.setCurrent` switch sur `mode` |
| FR-007, FR-008 (focus N selon mode) | `CommandRouter.handleDesktopFocus` lit `mode` |
| FR-009, FR-010 (current/list output) | `CommandRouter.handleDesktopList/current` |
| FR-011, FR-012 (drag/window display N adopte) | `Daemon.onDragDrop` + `CommandRouter.handleWindowDisplay` |
| FR-013 (mode global compat) | branch dans onDragDrop : si mode == .global, ne PAS modifier desktopID |
| FR-014, FR-015 (persistance per-display) | `DesktopPersistence.save(display:)` |
| FR-016 (triggers persistance) | hooks dans setCurrent + onDragDrop + recovery |
| FR-017 (load au boot) | `Daemon.bootstrap` étendu |
| FR-018 (load au branchement) | `handleDisplayConfigurationChange` étendu (SPEC-012 T026 hook) |
| FR-019 (conservation au débranchement) | suppression du dossier disque INTERDITE — uniquement le runtime state retire l'entry |
| FR-020 (orphelins ignorés) | matching N1/N2 + skip si pas de match |
| FR-021, FR-022, FR-023 (migration V2→V3) | `DesktopMigration.runIfNeeded()` au début du bootstrap |
| FR-024 (event display_id) | `EventBus.publish` avec payload étendu |
| FR-025 (events SPEC-012 préservés) | aucun changement aux events existants |
| FR-026 (compat mode global) | toute la logique conditionnée sur `mode == .global` |
| FR-027 (BTT inchangés) | aucun changement CLI verbe ; juste comportement interne |
