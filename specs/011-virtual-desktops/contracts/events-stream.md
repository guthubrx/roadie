# Contract — `roadie events --follow`

**Spec** : SPEC-011 | **Phase** : 1 | **Date** : 2026-05-02

Stream long-poll sur le socket Unix du daemon. Une connexion ouverte reçoit un flux JSON-lines des events internes au fur et à mesure qu'ils sont émis.

## Invocation

```bash
roadie events --follow
```

**Comportement** :
- Ouvre une connexion sur `~/.roadies/daemon.sock`.
- Envoie une requête initiale `{"cmd":"events.subscribe","args":{}}`.
- Lit en stream : une ligne JSON par event, terminée par `\n`.
- Bloque jusqu'à `Ctrl-C` ou déconnexion daemon.
- Exit code : 0 si Ctrl-C, 3 si daemon indisponible.

## Filtres optionnels

```bash
roadie events --follow --types desktop_changed,stage_changed
roadie events --follow --since 2026-05-01T00:00:00Z   # replay rétro (best-effort, ≤ 100 events)
```

## Schéma d'event

### `desktop_changed`

Émis à chaque bascule effective de desktop (jamais sur no-op).

```json
{
  "event": "desktop_changed",
  "from": "1",
  "to": "2",
  "from_label": "code",
  "to_label": "comm",
  "ts": 1714672389123
}
```

| Champ | Type | Description |
|---|---|---|
| `event` | string | Toujours `"desktop_changed"` |
| `from` | string | id du desktop quitté (string pour cohérence avec `to_label`) |
| `to` | string | id du desktop d'arrivée |
| `from_label` | string | Label si défini, sinon chaîne vide |
| `to_label` | string | Label si défini, sinon chaîne vide |
| `ts` | int64 | Unix epoch en millisecondes |

### `stage_changed`

Émis à chaque bascule de stage dans le desktop courant.

```json
{
  "event": "stage_changed",
  "desktop_id": "2",
  "from": "1",
  "to": "2",
  "ts": 1714672400000
}
```

| Champ | Type | Description |
|---|---|---|
| `event` | string | `"stage_changed"` |
| `desktop_id` | string | Desktop dans lequel le changement a lieu |
| `from` | string | Stage id quitté |
| `to` | string | Stage id d'arrivée |
| `ts` | int64 | Unix epoch en millisecondes |

## Garanties

- **Latence** : un event est écrit sur stdout du subscriber en moins de 50 ms après l'event interne (FR-016, SC-007).
- **Ordering** : ordre causal garanti sur un même desktop. Pas de garantie globale entre desktop_changed/stage_changed concurrents (rares).
- **Reconnect** : si le daemon redémarre, le subscriber doit relancer la commande. Pas de session persistante.
- **Cleanup** : à la déconnexion (SIGINT, EOF), le daemon retire le subscriber de sa liste interne (pas de fuite mémoire).

## Use cases typiques

### SketchyBar

```bash
# ~/.config/sketchybar/sketchybarrc
sketchybar --add event roadie_desktop_changed
roadie events --follow --types desktop_changed | while read -r line; do
    desk=$(echo "$line" | jq -r '.to')
    sketchybar --trigger roadie_desktop_changed DESKTOP="$desk"
done &
```

### Menu bar custom (xbar / SwiftBar)

Plugin shell qui pipe `roadie events --follow` et met à jour l'icône en temps réel.

### Logging / debug

```bash
roadie events --follow --types desktop_changed,stage_changed >> /tmp/roadie-events.jsonl &
```

## Format wire (socket interne)

Requête initiale du subscriber :

```json
{"cmd":"events.subscribe","args":{"types":["desktop_changed","stage_changed"]}}
```

Réponse initiale du daemon (header) :

```json
{"ok":true,"data":{"subscription_id":"abc123","subscribed_types":["desktop_changed","stage_changed"]}}
```

Puis stream d'events JSON-lines jusqu'à fermeture.

## Erreurs

| Code | Cause |
|---|---|
| `daemon_unavailable` | Socket non joignable |
| `subscribe_failed` | Daemon refuse la souscription (limite atteinte, max 16 subscribers concurrents) |
| `invalid_filter` | Type d'event inconnu dans `--types` |
