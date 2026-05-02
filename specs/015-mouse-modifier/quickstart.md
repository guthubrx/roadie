# Quickstart — SPEC-015 Mouse modifier drag & resize

## Activer la feature

1. Ouvre `~/.config/roadies/roadies.toml` et ajoute (ou laisse implicit pour les defaults) :

```toml
[mouse]
modifier = "ctrl"
action_left = "move"
action_right = "resize"
edge_threshold = 30
```

2. Recharger le daemon :
```bash
roadie daemon reload
# ou : ~/.local/bin/roadie-restart
```

## Tester drag-move

1. Maintenir **Ctrl** enfoncé.
2. **Cliquer gauche** au milieu d'une fenêtre (peu importe où).
3. Drag → la fenêtre suit le curseur.
4. Lâcher → fenêtre commit à sa nouvelle position. Si elle était tilée, elle est devenue floating.

## Tester drag-resize

1. **Ctrl + clic droit** au coin haut-gauche d'une fenêtre.
2. Drag de 100 px en haut-gauche → la fenêtre s'agrandit en haut-gauche, coin BR fixe.
3. Lâcher.

Variantes :
- Clic droit en bas-droite → resize coin BR (ancre = TL).
- Clic droit au milieu d'un bord → resize bord seul.
- Clic droit au centre exact → tomber sur le quadrant nearest après 1er pixel de drag.

## Customiser

```toml
[mouse]
modifier = "alt"             # changer pour Alt
action_left = "resize"       # inversé
action_right = "move"
action_middle = "move"       # clic molette aussi déplace
edge_threshold = 50          # zones de bord plus larges
```

`roadie daemon reload`.

## Désactiver

```toml
[mouse]
action_left = "none"
action_right = "none"
action_middle = "none"
```

Aucun bouton réagit, MouseRaiser fonctionne normalement (sans drag interférence).

## Debug

```bash
# Suivre les events drag
tail -f /tmp/roadied.log | grep -E "mouse-drag|drag-resize"
```

Les events ressemblent à :
```
mouse-drag-start wid=12345 mode=move quadrant=center
mouse-drag-end wid=12345 final_frame=[100,50,800,600]
```
