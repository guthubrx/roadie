# CLI Protocol — Multi-desktop V2

**Date** : 2026-05-01

Extension du protocole CLI V1. Toutes les commandes V1 (`windows`, `daemon`, `focus`, `move`, `resize`, `tiler`, `tree`, `balance`, `rebuild`, `stage`) sont **inchangées et continuent à fonctionner**. Le verbe `desktop` et `events` sont nouveaux.

---

## Verbe `desktop`

Manipule les desktops macOS (Spaces Mission Control) au niveau roadie. Toutes les sous-commandes nécessitent `multi_desktop.enabled = true` dans la config sauf `desktop list --json` (toujours autorisé en lecture).

### `roadie desktop list [--json]`

Liste tous les desktops actuellement connus de roadie (= ceux qu'il a déjà observés au moins une fois ou ceux pré-déclarés dans `[[desktops]]` config).

**Sortie texte par défaut** :
```
INDEX  UUID                                     LABEL    CURRENT  STAGES  WINDOWS
1      550e8400-e29b-41d4-a716-446655440000     code     *        2       5
2      f47ac10b-58cc-4372-a567-0e02b2c3d479     comm              1       3
3      6ba7b810-9dad-11d1-80b4-00c04fd430c8     -                 0       0
```

**Sortie JSON avec `--json`** :
```json
{
  "current_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "desktops": [
    {"index": 1, "uuid": "550e8400-...", "label": "code", "stage_count": 2, "window_count": 5},
    {"index": 2, "uuid": "f47ac10b-...", "label": "comm", "stage_count": 1, "window_count": 3},
    {"index": 3, "uuid": "6ba7b810-...", "label": null, "stage_count": 0, "window_count": 0}
  ]
}
```

### `roadie desktop focus <selector>`

Bascule vers le desktop indiqué via Mission Control natif macOS (délégation à SkyLight). Le daemon réagit automatiquement à la transition observée et charge l'état correspondant.

**Selectors supportés** :
- `prev` / `next` : navigation relative
- `first` / `last` : extrêmes
- `recent` : dernier desktop visité (back-and-forth)
- `back` : alias de `recent`
- `1`, `2`, `3` ... : index Mission Control (1-based)
- `<label>` : label utilisateur précédemment posé

**Comportement** :
- Si selector match `current_desktop` et `back_and_forth = true` (config) → bascule vers `recent` à la place
- Si selector inconnu → `error: unknown desktop selector "<value>"`, exit code 2

**Réponse** :
```json
{"status": "ok", "current_uuid": "f47ac10b-...", "current_index": 2}
```

### `roadie desktop current [--json]`

Retourne les infos du desktop actif.

**Sortie JSON** :
```json
{
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "index": 1,
  "label": "code",
  "current_stage_id": "1",
  "stage_count": 2,
  "window_count": 5,
  "tiler_strategy": "bsp"
}
```

### `roadie desktop label <name>`

Pose un label sur le desktop courant. Le label est persisté et utilisable comme selector partout.

**Exemple** :
```bash
roadie desktop label dev      # nomme le desktop courant "dev"
roadie desktop focus dev      # plus tard, bascule via le label
roadie desktop label ""       # retire le label
```

**Validation** :
- `name` accepté : alphanumérique + `-` `_`, max 32 chars, pas d'espaces ni accents
- `name` vide → retire le label

### `roadie desktop back`

Alias de `roadie desktop focus recent`. Utile pour les raccourcis rapides BTT.

---

## Verbe `events`

### `roadie events --follow [--filter <event-name>]`

Ouvre une connexion subscription au daemon et streame les events au fil de l'eau. Format JSON-lines (1 event = 1 ligne JSON, auto-flushed).

**Format**:
```
{"event": "desktop_changed", "ts": "...", "from": "...", "to": "...", "from_index": 1, "to_index": 2}
{"event": "stage_changed", "ts": "...", "desktop_uuid": "...", "from": "stage1", "to": "stage2"}
```

**Options** :
- `--filter <event-name>` : ne stream que cet event (peut être répété : `--filter desktop_changed --filter stage_changed`)
- `--since <timestamp>` : V3 (réservé, pas en V2)

**Comportement** :
- La connexion reste ouverte jusqu'à `Ctrl+C` ou perte du daemon
- Si daemon redémarre, le client se déconnecte et doit relancer la commande (pas d'auto-reconnect en V2)
- Pas de buffering : un event en cours d'émission est livré immédiatement

**Use cases** :
```bash
# Menu bar custom qui affiche le desktop courant
roadie events --follow --filter desktop_changed | jq -r '.to_index' | sketchybar -m ...

# Logging générique
roadie events --follow >> ~/.local/state/roadies/events.log
```

---

## Erreurs communes

| Code exit | Sens |
|---|---|
| 0 | Succès |
| 1 | Erreur générique (à éviter, préférer un code spécifique) |
| 2 | Mauvais usage CLI (selector invalide, args manquants) |
| 3 | Daemon non joignable |
| 4 | `multi_desktop.enabled = false` mais commande désactivée demandée |
| 5 | Desktop / stage cible introuvable |

---

## Compatibilité ascendante

- **Aucune commande V1 modifiée** : `roadie windows list`, `roadie stage *`, `roadie focus`, etc. fonctionnent à l'identique.
- Les commandes `roadie stage *` opèrent sur le **desktop courant** quand `multi_desktop.enabled = true`. Sur le state V1 unique sinon.
- Les 13 raccourcis BTT existants (focus/move/restart/stage 1+2 switch+assign) restent inchangés.
