# Events Stream — Multi-desktop V2

**Date** : 2026-05-01

Spécification du canal events temps réel exposé via `roadie events --follow`.

## Transport

- Socket Unix existant `~/.roadies/daemon.sock`
- Subscription via commande `events.subscribe` envoyée par le client `roadie events --follow`
- Le daemon push des messages JSON-lines au fil de l'eau, sans buffering
- Connexion bidirectionnelle : le client peut envoyer `events.unsubscribe` ou simplement fermer la connexion pour arrêter

## Schéma général

Chaque event = 1 ligne JSON terminée par `\n`. Champs communs :

| Champ | Type | Toujours présent | Description |
|---|---|---|---|
| `event` | string | ✅ | Nom de l'event (énum stable, ne renommer jamais sans bump version) |
| `ts` | ISO8601 string | ✅ | Timestamp UTC précision millisec, auto-généré côté daemon |
| `version` | int | ✅ | Schema version (V2 = 1) |

## Events V2 minimums

### `desktop_changed`

Émis quand l'utilisateur bascule de desktop macOS via Mission Control.

```json
{
  "event": "desktop_changed",
  "ts": "2026-05-01T13:42:51.832Z",
  "version": 1,
  "from": "550e8400-e29b-41d4-a716-446655440000",
  "from_index": 1,
  "from_label": "code",
  "to": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "to_index": 2,
  "to_label": "comm"
}
```

**Champs spécifiques** :
- `from` / `to` : UUID des desktops source et cible. `from` est `null` au premier boot du daemon (transition initiale).
- `from_index` / `to_index` : index Mission Control au moment de l'event (volatile mais utile pour menu bar).
- `from_label` / `to_label` : labels utilisateur si posés, sinon `null`.

### `stage_changed`

Émis quand l'utilisateur switch de stage (via `roadie stage <id>` ou raccourci ⌥1/⌥2).

```json
{
  "event": "stage_changed",
  "ts": "2026-05-01T13:43:00.123Z",
  "version": 1,
  "desktop_uuid": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "from": "1",
  "to": "2",
  "from_name": "Work",
  "to_name": "Personal"
}
```

**Champs spécifiques** :
- `desktop_uuid` : sur quel desktop le switch s'est produit (toujours = current desktop au moment du switch)
- `from` / `to` : `StageID` source et cible. `from` peut être `null` si premier stage activé.
- `from_name` / `to_name` : `displayName` correspondants si présents.

## Ordre garanti

- Si l'utilisateur bascule rapidement desktop A → desktop B → desktop A (dans la même seconde) → 3 events `desktop_changed` émis dans l'ordre, tous livrés.
- Pas de coalescing en V2.
- Pas de filtrage côté daemon : si plusieurs clients sont subscribed, tous reçoivent tous les events. Filtrage `--filter` s'applique côté client.

## Reconnect strategy

- En V2, pas de reconnect auto. Si le daemon redémarre, `roadie events --follow` se déconnecte et exit avec code 3. Le user-script doit lui-même boucler.
- En V3, ajouter `--retry` qui re-tente une connexion toutes les 1 s (max 60 s avant abandon).

## Events futurs (V3+, hors scope V2)

À titre indicatif, pas implémentés en V2 :
- `window_created` / `window_destroyed` (mirror des AX events)
- `window_focused`
- `tiler_strategy_changed`
- `stage_assigned` / `stage_unassigned`

## Format wire (interne daemon ↔ client roadie)

Au niveau du socket Unix, request/response est en JSON-lines (continuité V1). La commande `events.subscribe` ouvre un mode push où le daemon envoie des events asynchrones sans attente de request, jusqu'à ce que la connexion se ferme.

```
client: {"command": "events.subscribe"}
daemon: {"status": "ok", "subscribed": true}
daemon: {"event": "desktop_changed", ...}
daemon: {"event": "stage_changed", ...}
client: (close connection)
```

`roadie events --follow` se contente de re-streamer ces lignes vers stdout, en filtrant si `--filter` est présent.
