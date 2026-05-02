# Contracts — SPEC-013 Desktop par Display

**Date** : 2026-05-02 | **Phase** : 1

## 1. CLI / JSON-RPC commands (extension)

Tous les commandes existantes conservent leur surface. Modifications de **comportement** uniquement quand `mode == per_display`.

### `desktop.focus`

**Request** :
```json
{
  "command": "desktop.focus",
  "args": { "selector": "2" }
}
```

**Selector** : identique à V2 (`prev | next | recent | first | last | N | label`).

**Response** :
```json
{
  "ok": true,
  "data": {
    "from": 1,
    "to": 2,
    "display_id": 4,
    "mode": "per_display"
  }
}
```

**Comportement** :
- Mode `global` : change pour tous les écrans (V2). `display_id` retourne le primary.
- Mode `per_display` : change uniquement pour le display de la frontmost (FR-007). `display_id` retourne ce display.

### `desktop.list`

**Request** :
```json
{ "command": "desktop.list" }
```

**Response (mode `per_display`)** :
```json
{
  "ok": true,
  "data": {
    "mode": "per_display",
    "displays": [
      { "display_id": 1, "display_index": 1, "current": 1, "label": "Built-in" },
      { "display_id": 4, "display_index": 2, "current": 3, "label": "LG HDR 4K" }
    ],
    "desktops": [
      {
        "id": 1, "label": null, "stage_count": 1,
        "windows_by_display": { "1": 5, "4": 0 }
      },
      {
        "id": 3, "label": null, "stage_count": 1,
        "windows_by_display": { "1": 0, "4": 2 }
      }
    ]
  }
}
```

**Response (mode `global`)** :
```json
{
  "ok": true,
  "data": {
    "mode": "global",
    "current": 1,
    "desktops": [...]   // identique à V2
  }
}
```

### `desktop.current`

**Request** :
```json
{ "command": "desktop.current" }
```

**Response (mode `per_display`)** :
```json
{
  "ok": true,
  "data": {
    "mode": "per_display",
    "display_id": 4,
    "current": 3
  }
}
```

**Response (mode `global`)** : identique à V2 (`{ "current": 1 }`).

### `window.display` (extension SPEC-012)

**Request** : inchangée.

**Response** : inchangée mais **comportement étendu** :
- En mode `per_display`, le `desktopID` de la fenêtre déplacée est mis à jour à `currentByDisplay[targetDisplayID]` (FR-012).

---

## 2. Format TOML config

```toml
# ~/.config/roadies/roadies.toml

[desktops]
enabled = true
count = 10
mode = "per_display"   # NEW SPEC-013 : "global" (défaut) | "per_display"
default_id = 1
```

---

## 3. Format TOML persistance

### `~/.config/roadies/displays/<displayUUID>/current.toml`

```toml
current_desktop_id = 2
last_updated = "2026-05-02T13:45:12Z"
```

### `~/.config/roadies/displays/<displayUUID>/desktops/<id>/state.toml`

Format identique à SPEC-011 (réutilisé tel quel) :

```toml
[[windows]]
cgwid = 12345
bundle_id = "com.googlecode.iterm2"
title_prefix = "Default ~/.zsh — Mac"
expected_frame = [100.0, 50.0, 1024.0, 768.0]
display_uuid = "4DAC02A1-..."   # SPEC-012, conservé
stage_id = "1"
```

---

## 4. Events (extension)

### `desktop_changed` (event SPEC-011, payload étendu FR-024)

```json
{
  "event": "desktop_changed",
  "payload": {
    "from": "1",
    "to": "2",
    "display_id": "4",
    "mode": "per_display",
    "ts": "1714654512000"
  }
}
```

**Champ ajouté** : `display_id` (toujours présent). En mode global, `display_id` = ID du primary.

### `display_configuration_changed` (existant SPEC-012)

Inchangé.

### `display_changed` (existant SPEC-012)

Inchangé. `display_id` déjà présent.

---

## 5. Migration V2 → V3 (one-shot)

**Détection** :
- Au boot du daemon, vérifier `~/.config/roadies/desktops/` existence.
- Si présent ET `~/.config/roadies/displays/` absent ou vide → trigger migration.

**Algorithme** :
```
primaryUUID = DisplayRegistry.primary.uuid
mkdir -p ~/.config/roadies/displays/<primaryUUID>/
mv ~/.config/roadies/desktops ~/.config/roadies/displays/<primaryUUID>/desktops
# si state-current.toml existait dans l'ancienne racine, lire current et écrire :
echo "current_desktop_id = <N>" > ~/.config/roadies/displays/<primaryUUID>/current.toml
log("migration v2->v3 completed", { count: <ndesktops>, target: primaryUUID })
```

**Idempotence** : si `~/.config/roadies/desktops/` n'existe pas → pas d'action.

---

## 6. Erreurs et codes

| Cas | Code | Behavior |
|---|---|---|
| TOML mode invalide | warn log, no error | Fallback `mode = global` |
| `current.toml` corrompu pour un display | warn log | Fallback `current_desktop_id = 1` |
| `state.toml` ligne corrompue | debug log | Skip cette entry |
| Migration V2→V3 fail (perm denied) | error log | Continue avec defaults vides |
| Display rebranché mais pas d'historique disque | info log | Aucun restore, current = 1 |
