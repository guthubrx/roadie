# Contract — CLI `roadie display *`

**Spec** : SPEC-012 | **Phase** : 1 | **Date** : 2026-05-02

## `roadie display list`

**Stdout** :

```
INDEX  ID         NAME                     FRAME                  IS_MAIN  IS_ACTIVE  WINDOWS
1      1          Built-in Retina Display  0,0 2048x1280          *                   3
2      724592257  DELL U2723QE             -298,1280 3840x2160              *          5
```

**`--json`** :

```json
[
  {"index":1, "id":1, "uuid":"37D8...", "name":"Built-in Retina Display", "frame":[0,0,2048,1280], "visible_frame":[0,32,2048,1248], "is_main":true, "is_active":false, "windows":3},
  {"index":2, "id":724592257, "uuid":"AB12...", "name":"DELL U2723QE", "frame":[-298,1280,3840,2160], "visible_frame":[-298,1280,3840,2160], "is_main":false, "is_active":true, "windows":5}
]
```

## `roadie display current`

```
2  DELL U2723QE
```

`--json` :

```json
{"index":2, "id":724592257, "name":"DELL U2723QE"}
```

## `roadie display focus <selector>`

Selectors : `1..N` ou `prev`/`next`/`main`.

Exit codes : 0 succès, 2 selector invalide, 3 daemon down.

Comportement : focus la fenêtre frontmost de l'écran cible, ou la première fenêtre tilée s'il n'y a pas de frontmost connue. Si aucune fenêtre, no-op.

## Format wire (socket)

`{"version":"roadie/1","command":"display.list","args":{}}`

Réponse :
```json
{"ok":true,"data":{"displays":[...]}}
```

Codes d'erreur :
- `unknown_display` : selector hors range
- `daemon_unavailable`
- `internal_error`
