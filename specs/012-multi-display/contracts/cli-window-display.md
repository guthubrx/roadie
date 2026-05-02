# Contract — CLI `roadie window display <selector>`

**Spec** : SPEC-012 | **Phase** : 1 | **Date** : 2026-05-02

## Comportement

Déplace la fenêtre frontmost vers l'écran indiqué.

**Selectors** :
- `1..N` : index 1-based de l'écran cible
- `prev` : écran précédent (cyclique)
- `next` : écran suivant (cyclique)
- `main` : primary screen

**Exit codes** :
- 0 : succès
- 2 : selector invalide ou pas de fenêtre frontmost
- 3 : daemon down

## Stdout (succès)

```
moved: cgwid=12345 from=1 to=2
```

`--json` :

```json
{"ok":true,"cgwid":12345,"from":1,"to":2,"new_frame":[2400,200,800,600]}
```

## Stdout (erreurs)

```
roadie: error [unknown_display] display 5 does not exist (have 2)
```

```
roadie: error [no_focused_window] no focused window to move
```

## Comportement détaillé

### Fenêtre tilée

1. Retirer du tree de l'écran source (`LayoutEngine.removeWindow(from: srcID)`).
2. Calculer nouvelle frame : centre = `dst.visibleFrame.center`, taille préservée si elle entre dans `dst.visibleFrame`, sinon clamp à 80% du visibleFrame.
3. `AXReader.setBounds(wid, newFrame)`.
4. Insérer dans le tree de l'écran cible (`LayoutEngine.insertWindow(into: dstID)`).
5. Update `DesktopRegistry.WindowEntry.displayUUID = dst.uuid`.
6. `applyLayout(displayID: src)` puis `applyLayout(displayID: dst)`.

### Fenêtre flottante (subrole.isFloatingByDefault)

1. Calculer nouvelle frame : centre `dst.visibleFrame`, taille préservée.
2. `AXReader.setBounds(wid, newFrame)`.
3. Update `DesktopRegistry.WindowEntry.displayUUID = dst.uuid`.
4. Pas d'`applyLayout` (floating).

## Format wire (socket)

```json
{"version":"roadie/1","command":"window.display","args":{"selector":"2"}}
```

Réponse succès :
```json
{"ok":true,"data":{"cgwid":12345,"from":1,"to":2,"new_frame":[2400,200,800,600]}}
```

## Codes d'erreur

| Code | Description |
|---|---|
| `unknown_display` | Selector ne résout pas un écran connecté |
| `no_focused_window` | Pas de fenêtre frontmost |
| `move_failed` | AX a refusé le setBounds (rare) |
| `daemon_unavailable` |  |

## Use cases

### BTT shortcut

⌥+⇧+→ : `~/.local/bin/roadie window display next`

⌥+⇧+1, ⌥+⇧+2 : `~/.local/bin/roadie window display 1` etc.

### Script

```bash
# Déplacer toutes les fenêtres iTerm sur l'écran 2
for wid in $(roadie windows list --json | jq '.windows[] | select(.bundle == "com.googlecode.iterm2") | .id'); do
    roadie window focus $wid
    roadie window display 2
done
```
