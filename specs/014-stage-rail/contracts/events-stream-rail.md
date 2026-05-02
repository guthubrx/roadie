# Contract — Extensions `roadie events --follow` pour SPEC-014

**Status**: Draft
**Spec**: SPEC-014 stage-rail
**Type**: Extension du flux events JSON-lines existant (SPEC-003)

## Vue d'ensemble

SPEC-014 ajoute trois nouveaux types d'événements émis par le daemon sur le canal `roadie events --follow`, conformes au schema common (`event`, `ts`, `version`, payload spécifique).

## Événement `wallpaper_click`

Émis quand le `WallpaperClickWatcher` détecte un click souris hors de toute fenêtre tracked et hors du rail.

### Format

```json
{
  "event": "wallpaper_click",
  "ts": "2026-05-02T17:31:05.456Z",
  "version": 1,
  "x": 800,
  "y": 600,
  "display_id": 1234
}
```

### Champs

| Champ | Type | Description |
|---|---|---|
| `x` | Int | Coord X global (NS, origine bas-gauche du primary) |
| `y` | Int | Coord Y global |
| `display_id` | UInt32 | `CGDirectDisplayID` de l'écran où le click est tombé |

### Émission

- Émis **uniquement** si `[fx.rail] wallpaper_click_to_stage = true` ET `roadie-rail` tourne (`~/.roadies/rail.pid` valide).
- Side-effect : avant d'émettre, le daemon a déjà créé la nouvelle stage et migré les fenêtres tilées (cf US4). L'event sert à informer les subscribers (rail, UI debug) que ça vient de se passer.

### Use case

- Le rail rafraîchit son état (la nouvelle stage apparaît sans polling).
- Outils d'analyse pour comprendre le pattern d'usage utilisateur.

## Événement `stage_renamed`

Émis quand l'utilisateur renomme une stage (via le rail, US5, ou via CLI `roadie stage rename`).

### Format

```json
{
  "event": "stage_renamed",
  "ts": "2026-05-02T17:31:10.000Z",
  "version": 1,
  "stage_id": "1",
  "old_name": "Work",
  "new_name": "Coding",
  "desktop_id": 3
}
```

### Champs

| Champ | Type | Description |
|---|---|---|
| `stage_id` | String | Identifiant de la stage renommée |
| `old_name` | String | Ancien nom |
| `new_name` | String | Nouveau nom |
| `desktop_id` | Int | Desktop virtuel auquel appartient la stage |

### Use case

- Le rail met à jour le titre de la carte.
- Les BTT et scripts utilisateurs peuvent réagir au renommage.

## Événement `thumbnail_updated`

Émis quand `SCKCaptureService` capture une nouvelle vignette pour une fenêtre observée.

### Format

```json
{
  "event": "thumbnail_updated",
  "ts": "2026-05-02T17:31:12.500Z",
  "version": 1,
  "wid": 12345
}
```

### Champs

| Champ | Type | Description |
|---|---|---|
| `wid` | UInt32 | CGWindowID dont la vignette a changé |

### Émission

- À chaque cycle de capture (toutes les 2 s par fenêtre observée).
- N'inclut PAS les bytes PNG (trop lourd pour un event push). Le subscriber qui veut la vignette appelle `roadie window thumbnail <wid>` pour la récupérer.

### Use case

- Le rail invalide son cache local et re-fetch la vignette.

## Subscription depuis le rail

Le rail invoque au démarrage :

```bash
roadie events --follow --types wallpaper_click,stage_renamed,thumbnail_updated,stage_changed,desktop_changed,window_assigned,window_created,window_destroyed
```

Le filtre `--types` (extension SPEC-003) limite le flux aux événements pertinents pour le rail, économisant la bande passante du socket.

## Garanties

- **Ordering** : monotone par `ts`. Un `wallpaper_click` est toujours suivi (≤ 100 ms) par les `stage_changed` et `window_assigned` correspondants.
- **At-least-once** : si le subscriber rate des events durant une déconnexion, ils ne sont **pas** rejoués (best effort). Le rail doit re-fetch l'état complet via `stage list` après reconnexion.
- **Backpressure** : si le subscriber lit lentement, le daemon peut buffer jusqu'à 1000 events puis drop les plus anciens (log warning).

## Test acceptance (bash)

`tests/14-events-rail.sh` :
1. Subscriber : `roadie events --follow --types wallpaper_click > events.log &`
2. Lancer `roadie-rail`.
3. Click sur le bureau Finder (osascript `tell app "Finder" to activate; click at {800,600}`).
4. Lire `events.log` → vérifier présence d'une ligne JSON avec `"event":"wallpaper_click"` et `x:800, y:600`.
5. Killer le subscriber, killer roadie-rail.

`tests/14-events-rename.sh` :
1. Lancer un subscriber sur `stage_renamed`.
2. `roadie stage rename 1 "Coding"`.
3. Vérifier l'event reçu avec `old_name`, `new_name` corrects.
