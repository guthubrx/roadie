# Quickstart — SPEC-016 Yabai-parity tier-1

**Status**: Done
**Last updated**: 2026-05-02
**Audience**: utilisateur final qui veut activer rules, signals et focus-follows-mouse, ou qui migre depuis yabai.

## Prérequis

- macOS 14+
- `roadied` installé et tournant (cf. SPEC-002 quickstart)
- Permission Accessibility accordée à `roadied.app`
- SPEC-015 (mouse modifier) installée → permission Input Monitoring déjà active (mutualisée par MouseFollowFocusWatcher)

## 1. Activer `focus_follows_mouse` — naviguer sans clic

L'idée : déplacer le curseur sur une fenêtre voisine la met automatiquement en focus, après un court délai d'idle.

```bash
# Édite ~/.config/roadies/roadies.toml
cat >> ~/.config/roadies/roadies.toml <<'EOF'

[mouse]
focus_follows_mouse = "autofocus"   # ou "autoraise" pour faire passer la fenêtre devant
idle_threshold_ms = 200             # 200ms d'immobilité avant migration
EOF

# Recharge sans redémarrer le daemon
roadie daemon reload
```

**Test** : ouvre 2 fenêtres côte à côte. Bouge le curseur de l'une à l'autre **sans cliquer**. Après 200 ms, la deuxième prend le focus (titre s'éclaircit, border switch via SPEC-008).

**Désactiver** : `focus_follows_mouse = "off"` + reload.

## 2. Activer `mouse_follows_focus` — curseur suit le focus clavier

Indispensable si tu utilises `focus_follows_mouse` : sinon le curseur reste sur l'ancienne fenêtre quand tu changes de focus au clavier, et `focus_follows_mouse` te re-bascule sur l'ancienne. Frustrant.

```toml
[mouse]
focus_follows_mouse = "autofocus"
mouse_follows_focus = true
```

```bash
roadie daemon reload
```

**Test** : `roadie focus right` (ou ton BTT shortcut) → le curseur se téléporte au centre de la nouvelle fenêtre focused. Instantané (< 1 frame).

## 3. Désactiver le tiling pour 1Password mini

Cas typique : 1Password mini est une mini-fenêtre qui ne doit JAMAIS entrer dans le tile BSP.

```toml
[[rules]]
app = "1Password"
title = "1Password mini"
manage = "off"
```

```bash
roadie daemon reload
```

**Test** : ferme et rouvre 1Password mini. La fenêtre apparaît à sa position d'origine, **pas** dans le tile.

**Vérifier l'application de la rule** :
```bash
roadie rules list
# Voir la rule à l'index 0 avec effects=manage=off
```

## 4. Forcer Slack toujours sur le desktop 5

```toml
[[rules]]
app = "Slack"
space = 5
```

**Test** : ferme Slack. Ouvre-le. Il apparaît directement sur le desktop 5 (équivalent `roadie window desktop 5` automatique).

## 5. Floating + sticky pour Activity Monitor

```toml
[[rules]]
app = "Activity Monitor"
float = true
sticky = true
```

**Test** : ouvre Activity Monitor. Il est floating (pas tilé). Switch de desktop : il reste visible (sticky).

## 6. Notifier au démarrage de Slack

Cas signal : exécuter une commande shell quand Slack se lance.

```toml
[[signals]]
event = "application_launched"
app = "Slack"
action = "osascript -e 'display notification \"Slack started\" with title \"roadie\"'"
```

```bash
roadie daemon reload
```

**Test** : quitte Slack, relance-le. Une notification macOS apparaît.

**Voir les signals chargés** :
```bash
roadie signals list
```

## 7. Logger toutes les fenêtres focused

```toml
[[signals]]
event = "window_focused"
action = "echo \"$(date -Iseconds) $ROADIE_WINDOW_BUNDLE $ROADIE_WINDOW_TITLE\" >> /tmp/focus.log"
```

**Test** : clique sur 5 fenêtres différentes. Vérifie `/tmp/focus.log` :
```
2026-05-02T18:32:15+02:00 com.apple.Terminal Terminal — bash
2026-05-02T18:32:18+02:00 com.apple.Safari Apple
...
```

## 8. Pré-décider où le prochain split aura lieu

```bash
# 3 fenêtres tilées BSP, focus sur A
roadie window insert south    # next window splittera EN BAS de A
# Ouvre une 4e app
# Résultat : la nouvelle fenêtre apparaît sous A, pas à droite (default split-largest)
```

Le hint expire après 120 s s'il n'est pas consommé.

**Annuler avant expiration** : poser un nouveau hint (remplace) ou fermer A (orphelin retiré).

**Configurer le délai** :
```toml
[insert]
hint_timeout_ms = 60000      # 1 minute au lieu de 2
```

## 9. Échanger 2 fenêtres sans casser le layout

Différent de `roadie move` (qui réorganise l'arbre).

```bash
# Layout: [A | B / C], focus B
roadie window swap left
# Résultat: [B | A / C], focus toujours sur B (qui a juste changé de position)
# Le split horizontal A/C est préservé, les ratios aussi
```

## 10. Migration depuis `~/.yabairc`

Mapping 1-pour-1 pour 80 % des champs courants (cf. SC-016-09) :

| yabai | roadie |
|---|---|
| `yabai -m rule --add app="Slack" manage=off` | `[[rules]] app="Slack"`<br>`manage="off"` |
| `yabai -m rule --add app="Slack" space=5` | `[[rules]] app="Slack"`<br>`space=5` |
| `yabai -m rule --add app="Activity Monitor" sticky=on` | `[[rules]] app="Activity Monitor"`<br>`sticky=true` |
| `yabai -m rule --add app="Calculator" grid="4:4:3:3:1:1"` | `[[rules]] app="Calculator"`<br>`grid="4:4:3:3:1:1"` |
| `yabai -m rule --add app="Safari" title="^Settings$"` | `[[rules]] app="Safari"`<br>`title="^Settings$"` |
| `yabai -m rule --add app="WezTerm" display=2` | `[[rules]] app="WezTerm"`<br>`display=2` |
| `yabai -m signal --add event=window_focused action="..."` | `[[signals]] event="window_focused"`<br>`action="..."` |
| `yabai -m signal --add event=window_created app="Slack" action="..."` | `[[signals]] event="window_created"`<br>`app="Slack"`<br>`action="..."` |
| `yabai -m config focus_follows_mouse autofocus` | `[mouse] focus_follows_mouse="autofocus"` |
| `yabai -m config mouse_follows_focus on` | `[mouse] mouse_follows_focus=true` |
| `yabai -m window --swap east` | `roadie window swap right` |
| `yabai -m window --insert east` | `roadie window insert east` |

**Différences notables vs yabai** :
- Pas de `--add` dynamique : roadie ne supporte que l'édition TOML + `daemon reload`. Plus simple, plus prévisible.
- `space=N` est immédiat : la fenêtre migre dès `window_created` (yabai a parfois un delay).
- `display=N` utilise l'index 1-based de `NSScreen.screens` (= ce que retourne `roadie display list`).
- Anti-pattern `app=".*"` est **rejeté** au parsing (yabai accepte mais te casse le tiling). Utilise un filtre précis ou combine avec `title=`.
- Re-entrancy guard automatique : un signal `action` qui appelle `roadie ...` ne déclenche pas de cascade (yabai ne protège pas contre ça).

## 11. Diagnostic & troubleshooting

### Vérifier que les rules sont bien chargées

```bash
roadie rules list
# Affiche INDEX, APP, TITLE, EFFECTS

# Avec les rules rejetées (anti-pattern, regex cassé)
roadie rules list --json | jq .rejected_at_parse
```

### Vérifier les signals

```bash
roadie signals list

# Métriques live (queue depth, dispatched/dropped/timeouts)
roadie daemon status | jq .signals
```

### Forcer la ré-application des rules sur les fenêtres existantes

Par défaut, les rules ne s'appliquent qu'aux **nouvelles** fenêtres (sécurité). Pour appliquer rétroactivement :

```bash
roadie rules apply --all
# [rules] re-applying 6 rules to 12 existing windows...
# [rules] applied: rule #0 (1Password) → wid=12345
# done. 3 rules applied.
```

### Logs

```bash
# Logs daemon (rules + signals + mouse-follow)
log stream --predicate 'subsystem == "local.roadies"' --info

# Filtrer rules uniquement
log stream --predicate 'subsystem == "local.roadies" AND category == "rules"'
```

| Symptôme | Cause probable | Solution |
|---|---|---|
| Rule semble ignorée | Anti-pattern rejeté au parsing | `roadie rules list --json` voir `rejected_at_parse` |
| Signal ne s'exécute pas | Filtre `app=` trop strict ou regex cassé | Tester sans filtre d'abord, puis ajouter |
| Cascade infinie suspectée | Signal qui crée fenêtres | Vérifier `ROADIE_INSIDE_SIGNAL=1` dans l'env de l'action |
| `focus_follows_mouse` ne fait rien | Permission Input Monitoring non accordée | Vérifier Réglages Système (héritée de SPEC-015) |
| `mouse_follows_focus` ne téléporte pas | Focus changé via clic souris | Le warp est skippé (curseur déjà sur la fenêtre) |
| Hint `--insert` ne se consomme pas | Fenêtre apparue sur autre display | Hint reste actif sur le tree d'origine — normal |
| Action shell timeout | > 5 s par défaut | Refactor en async/queue OU augmenter `[signals] timeout_ms` (max 30 s recommandé) |

## 12. Bonnes pratiques

### Rules

- Toujours combiner `app=` avec `title=` si tu utilises un regex large.
- Tester chaque rule isolément (`roadie rules list` après chaque ajout).
- Préférer `manage=off` à `float=true` quand tu veux juste exclure du BSP (sémantique plus claire).
- `reapply_on_title_change=true` est coûteux (perf) → réservé aux apps multi-tabs (browsers).

### Signals

- Actions courtes (< 100 ms idéalement, < 1 s acceptable).
- Actions longues → écrire dans une file ou déclencher un `launchctl`.
- Pas de `nohup`/`setsid` qui contournent le re-entrancy guard.
- Logger volumineux → rediriger vers un fichier (pas stdout/stderr de l'action).

### Focus follow

- Combiner `focus_follows_mouse="autofocus"` (pas autoraise) avec `mouse_follows_focus=true` est la combo la plus naturelle pour un tiling (testé daily driver).
- `idle_threshold_ms` plus court (100 ms) = plus réactif mais plus de jitter perçu. 200-300 ms est le sweet spot.

## 13. Hors scope V1 (à venir)

- `[[rules]] enabled = false` (désactivation temporaire) — V2
- `[[signals]] one_shot = true` (auto-désactive après 1 trigger) — V2
- Stack mode local + `focus stack.next/prev` + `--insert stack` réel → **SPEC-017** dédiée
- Mission Control / show-desktop → SPEC future (gap B1)
- Padding/gaps dynamiques par space → SPEC future (gap B2)
- Layers / topmost → SPEC-019 prévue (gap B6)

Voir `docs/decisions/ADR-006-yabai-feature-gap-analysis.md` (interne, gitignored) pour la liste complète des gaps yabai et leur priorisation.
