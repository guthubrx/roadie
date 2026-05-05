# Quickstart — SPEC-026 WM-Parity

## Prérequis

- `roadied` installé et tournant (vérifier `roadie ping`)
- `~/.config/roadies/roadies.toml` existe

## Activation feature par feature

### Quick-wins commandes (US1) — pas d'activation requise

```bash
roadie tiling balance
roadie tiling rotate 90
roadie tiling mirror x
```

Disponibles immédiatement sans modif TOML.

### Smart gaps solo (US2)

Éditer `~/.config/roadies/roadies.toml` :

```toml
[tiling]
smart_gaps_solo = true
```

Puis : `roadie daemon reload`.

**Test** : ouvrir une seule fenêtre tilée → elle occupe tout `visibleFrame` du display.

### Scratchpad (US3)

```toml
[[scratchpads]]
name = "term"
cmd = "open -na 'iTerm'"
```

Puis : `roadie daemon reload`.

**Test** : `roadie scratchpad toggle term` → iTerm apparaît. Re-exécuter → disparaît. Re-exécuter → revient.

### Sticky cross-stage (US4)

```toml
[[rules]]
match.bundle_id = "com.tinyspeck.slackmacgap"
sticky_scope = "stage"
```

Puis : `roadie daemon reload` + relancer Slack.

**Test** : Slack visible sur stage 1, switcher sur stage 2 → Slack toujours là.

### Follow focus bidirectionnel (US5)

```toml
[focus]
focus_follows_mouse = true
mouse_follows_focus = true
```

Puis : `roadie daemon reload`.

**Test** :
- Survoler une fenêtre → elle prend le focus après 100ms.
- Faire `cmd+L` (focus right) → le curseur saute au centre de la fenêtre droite.

### Signal hooks (US6)

```toml
[signals]
enabled = true

[[signals]]
event = "window_focused"
cmd = "afplay /System/Library/Sounds/Tink.aiff"
```

Puis : `roadie daemon reload`.

**Test** : changer le focus → entendre un Tink à chaque changement.

## Désactivation

Pour désactiver une feature : commenter/retirer la clé TOML correspondante, puis `roadie daemon reload`.

Pour le kill-switch global signals :

```toml
[signals]
enabled = false
```

## Vérification globale

```bash
roadie config check   # affiche les sections actives
roadie ping           # vérifie le daemon
```

Logs : `tail -f ~/.local/state/roadies/daemon.log` pour observer les events et signal exec.

## Rollback

Backup avant modif :

```bash
cp ~/.config/roadies/roadies.toml ~/.config/roadies/roadies.toml.bak
```

Pour revenir : `cp ~/.config/roadies/roadies.toml.bak ~/.config/roadies/roadies.toml && roadie daemon reload`.
