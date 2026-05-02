# Contract — CLI & IPC `rules` (US2 / FR-A1-*)

**Status**: Done
**Last updated**: 2026-05-02

## 1. Format TOML `[[rules]]`

Section `array of tables` dans `~/.config/roadies/roadies.toml`. Ordre du fichier = ordre d'évaluation (premier match wins).

### Schema

```toml
[[rules]]
# === Filtres (au moins UN requis) ===
app = "string"             # exact ou regex (cf. heuristique R-002), case-insensitive
title = "string"           # regex, case-insensitive (optionnel)

# === Effets (au moins UN requis) ===
manage = "on" | "off"      # tilable ou non
float = true | false       # sortir du BSP, fenêtre flottante
sticky = true | false      # visible sur tous les desktops virtuels
space = 1..16              # desktop virtuel cible
display = 1..N             # display cible (1-based, NSScreen.screens index)
grid = "R:C:r:c:w:h"       # placement grille (R=rows, C=cols, r=row, c=col, w=width, h=height)

# === Comportement ===
reapply_on_title_change = true | false   # default false (perf)
```

### Exemples

```toml
# 1Password mini : ne pas tiler
[[rules]]
app = "1Password"
title = "1Password mini"
manage = "off"

# Slack toujours sur desktop 5
[[rules]]
app = "Slack"
space = 5

# Activity Monitor : floating + visible partout
[[rules]]
app = "Activity Monitor"
float = true
sticky = true

# WezTerm : forcer sur display 2
[[rules]]
app = "WezTerm"
display = 2

# Calculator : grille 4×4, coin bas-droit, taille 1×1
[[rules]]
app = "Calculator"
grid = "4:4:3:3:1:1"

# Browser Settings : re-évalué quand le titre change (tab switch)
[[rules]]
app = "com.apple.Safari"
title = "^Settings$"
float = true
reapply_on_title_change = true
```

## 2. Sémantique d'évaluation

### Quand

- Au boot du daemon (sur les fenêtres existantes : NON, sauf via `rules apply --all`)
- À chaque event `window_created`
- À l'event `window_title_changed` SI au moins une rule a `reapply_on_title_change = true` ET matche le nouveau title

### Comment

1. Pour chaque `RuleDef` dans l'ordre du TOML :
   - Match `app` (literal exact case-insensitive sur `bundleID` ou `localizedName`, OU regex case-insensitive selon heuristique R-002).
   - Si `title != nil` : match regex sur le title courant.
   - Si TOUS les filtres présents matchent → **STOP**, applique les effets.
2. Aucun match → no-op (la fenêtre garde le comportement default).

### Application des effets (ordre d'exécution)

Quand une rule matche, ses effets sont appliqués dans cet ordre **synchrone** :

1. `manage` → `WindowRegistry.setTileable(wid, manage == .on)`
2. `float` → si `true`, exclu du BSP (équivalent `tiling.reserve <wid> false`)
3. `sticky` → `StickyManager.setSticky(wid, true)`
4. `space` → `DesktopRegistry.assign(wid, toDesktop: space)`
5. `display` → `DisplayManager.move(wid, toDisplay: display)`
6. `grid` → `LayoutEngine.placeOnGrid(wid, grid)`

**Race avec SPEC-011 desktop assignment** : les rules sont évaluées **synchronement avant** le routing initial de `DesktopRegistry`. Donc `space=N` rule **gagne** sur le desktop default. (cf. R-004 risque mitigé)

## 3. CLI

### `roadie rules list`

Liste les rules chargées avec index 0-based.

```bash
$ roadie rules list
INDEX  APP             TITLE             EFFECTS
0      1Password       1Password mini    manage=off
1      Slack           -                 space=5
2      Activity Monitor -                float=true, sticky=true
3      WezTerm         -                 display=2
4      Calculator      -                 grid=4:4:3:3:1:1
5      Safari          ^Settings$        float=true, reapply_on_title_change
```

**Avec `--json`** :
```bash
$ roadie rules list --json
{
  "rules": [
    {"index": 0, "app": "1Password", "title": "1Password mini", "effects": {"manage": "off"}},
    {"index": 1, "app": "Slack", "title": null, "effects": {"space": 5}},
    ...
  ],
  "rejected_at_parse": [
    {"index": 6, "reason": "anti-pattern: matches all", "raw": "app = '.*'"}
  ]
}
```

### `roadie rules apply --all`

Re-évalue toutes les rules sur **toutes** les fenêtres existantes. Opt-in pour éviter side effects au reload normal.

```bash
$ roadie rules apply --all
[rules] re-applying 6 rules to 12 existing windows...
[rules] applied: rule #0 (1Password) → wid=12345
[rules] applied: rule #1 (Slack) → wid=23456 (moved to desktop 5)
[rules] applied: rule #2 (Activity Monitor) → wid=34567 (float + sticky)
[rules] no match: 9 windows
done. 3 rules applied.
```

### Pas de `roadie rules add/remove` dynamique

L'édition se fait dans `roadies.toml` puis `roadie daemon reload`. Cohérent avec le pattern de toutes les autres sections de config (déjà éprouvé SPEC-002 → SPEC-015).

## 4. IPC (socket Unix)

### `rules.list`

**Requête** :
```json
{"cmd": "rules.list"}
```

**Réponse OK** :
```json
{
  "status": "ok",
  "data": {
    "rules": [
      {
        "index": 0,
        "app": "1Password",
        "title": "1Password mini",
        "effects": {"manage": "off"}
      }
    ],
    "rejected_at_parse": []
  }
}
```

### `rules.apply`

**Requête** :
```json
{"cmd": "rules.apply", "args": {"all": true}}
```

**Réponse OK** :
```json
{
  "status": "ok",
  "data": {
    "rules_evaluated": 6,
    "windows_processed": 12,
    "applications": [
      {"rule_index": 0, "wid": 12345, "effect_summary": "manage=off"},
      {"rule_index": 1, "wid": 23456, "effect_summary": "space=5"}
    ],
    "no_match": 9
  }
}
```

## 5. Erreurs

| Code | Cas | Message |
|---|---|---|
| `parse_error` | TOML invalide globalement | `failed to parse roadies.toml at line N: <reason>` |
| `rule_rejected` | Anti-pattern detecté | `rule #N: pattern would match all windows (use specific filter)` |
| `rule_invalid_field` | Valeur hors bornes | `rule #N: space must be in 1..16, got 99` |
| `rule_regex_invalid` | Regex non compilable | `rule #N: regex 'app' invalid: 'unterminated bracket'` |

Les erreurs au parsing **n'arrêtent pas le daemon**. Les rules valides sont chargées, les invalides sont skippées, les erreurs sont disponibles via `rules.list`.

## 6. Évolutions futures (hors scope V1)

- `[[rules]] note = "free text"` pour annoter
- `[[rules]] priority = N` pour réordonner sans déplacer dans le TOML
- `[[rules]] enabled = false` pour désactiver temporairement
- Match négatif : `app_not = "Slack"`
- Wildcards numériques : `space = "any"` ou `display = "primary"`

À considérer en V2 selon retour utilisateur.
