# Contract — Stage events stream (V2 enriched)

**Status**: Draft
**Spec**: SPEC-018 stages-per-display
**Type**: Extension du flux `roadie events --follow`

## Vue d'ensemble

Tous les events `stage_*` (existants et nouveaux) incluent désormais `display_uuid` et `desktop_id` dans leur payload. Cela permet aux consommateurs (rail UI SPEC-014, scripts SketchyBar, automations) de filtrer correctement par scope.

Un nouvel event `migration_v1_to_v2` est émis une seule fois au premier boot V2.

## Subscribe

```bash
roadie events --follow --types stage_changed,stage_created,stage_renamed,stage_deleted,stage_assigned,migration_v1_to_v2
```

## Events couverts

### `stage_changed` (enriched)

Émis lors d'un switch de stage (`stage.switch` ou bascule auto via stage manager).

```json
{
  "event": "stage_changed",
  "ts": "2026-05-02T19:30:00.000Z",
  "version": 1,
  "from": "1",
  "to": "2",
  "display_uuid": "37D8832A-2D66-4A47-9B5E-39DA5CF2D85F",
  "desktop_id": 1
}
```

**Mode `global`** : `display_uuid: ""`, `desktop_id: 0` (sentinel).

### `stage_created` (enriched)

Émis sur `stage.create` ou lazy-create via `stage.assign`.

```json
{
  "event": "stage_created",
  "ts": "...",
  "version": 1,
  "stage_id": "3",
  "display_name": "Comm",
  "display_uuid": "37D8832A-...",
  "desktop_id": 1
}
```

### `stage_renamed` (enriched, déjà existant SPEC-014)

Émis sur `stage.rename`.

```json
{
  "event": "stage_renamed",
  "ts": "...",
  "version": 1,
  "stage_id": "2",
  "old_name": "Default",
  "new_name": "Code",
  "display_uuid": "37D8832A-...",
  "desktop_id": 1
}
```

### `stage_deleted` (enriched)

Émis sur `stage.delete` (sauf stage 1 immortel).

```json
{
  "event": "stage_deleted",
  "ts": "...",
  "version": 1,
  "stage_id": "5",
  "display_uuid": "37D8832A-...",
  "desktop_id": 1
}
```

### `stage_assigned` (enriched)

Émis sur `stage.assign` quand une fenêtre est assignée à une stage.

```json
{
  "event": "stage_assigned",
  "ts": "...",
  "version": 1,
  "wid": 12345,
  "stage_id": "2",
  "display_uuid": "37D8832A-...",
  "desktop_id": 1
}
```

### `migration_v1_to_v2` (NEW, one-shot)

Émis une seule fois au premier boot avec `mode = per_display` ET stages V1 détectés.

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

Si la migration échoue partiellement (`partialMigration` error) :

```json
{
  "event": "migration_v1_to_v2",
  "ts": "...",
  "version": 1,
  "migrated_count": 2,
  "backup_path": "/Users/moi/.config/roadies/stages.v1.bak",
  "target_display_uuid": "37D8832A-...",
  "duration_ms": 12,
  "partial": true,
  "remaining_files": ["3.toml", "4.toml", "5.toml"]
}
```

## Garanties

- **Ordering** : strictement monotone par `ts` au sein d'un même type d'event
- **At-least-once** : un event peut être réémis en cas de reconnexion subscriber (consommer doit être idempotent ou utiliser `ts` pour dédup)
- **Schema version** : `version: 1` pour V2. Bump si breaking change futur.

## Cas d'usage rail UI (SPEC-014)

Le rail panel sur Display 1 souscrit avec filtre côté client :

```swift
eventStream.onEvent = { name, payload in
    let scope = currentPanelScope()  // (D1_uuid, currentDesktopForD1)
    let evtUUID = payload["display_uuid"] as? String ?? ""
    let evtDesk = payload["desktop_id"] as? Int ?? 0
    if evtUUID == scope.uuid && evtDesk == scope.desktopID {
        refreshUI()
    }
}
```

Cela évite que les changements sur D2 bouleversent l'UI de D1.

## Test acceptance (bash)

`tests/18-stage-events-scope.sh` :
1. Lancer `roadie events --follow --types stage_created > /tmp/events.log &`
2. Curseur sur D1, `roadie stage assign 9` → vérifier event avec `display_uuid` D1
3. Curseur sur D2, `roadie stage assign 9` → vérifier event avec `display_uuid` D2
4. `kill` le subscriber, vérifier les 2 events dans `/tmp/events.log`
