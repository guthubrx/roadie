# Quickstart — SPEC-013 Desktop par Display

## Activer le mode per_display

1. Éditer `~/.config/roadies/roadies.toml` :
   ```toml
   [desktops]
   enabled = true
   count = 10
   mode = "per_display"   # ← ajouter cette ligne
   ```

2. Recharger la config :
   ```bash
   roadie daemon reload
   ```

3. Tester :
   ```bash
   # Sur le LG HDR 4K (frontmost), bascule desktop 2
   roadie desktop focus 2

   # Vérifier : seul le LG a basculé
   roadie desktop list
   # ID    LABEL    BUILT-IN    LG HDR 4K
   # 1     —        *           —
   # 2     —        —           *
   ```

## Tester drag cross-display

1. Sur built-in, créer/ouvrir une fenêtre quelconque (ex: TextEdit).
2. Sur LG HDR 4K, basculer sur desktop 3 : `roadie desktop focus 3`.
3. Drag la fenêtre du built-in vers le LG.
4. Au lâcher, elle adopte desktop 3 et reste visible sur le LG.

## Tester recovery écran

1. État avant : LG branché, desktop 2 actif, 3 fenêtres dessus.
2. Débrancher le LG.
3. Les 3 fenêtres apparaissent sur le built-in (frames clampées au visibleFrame).
4. Rebrancher le LG.
5. Les 3 fenêtres retournent automatiquement sur le LG à leurs positions d'origine, current = 2.

## Bascule de mode à chaud

```toml
mode = "global"  # ← repasser en V2
```
Puis `roadie daemon reload`. Tous les écrans se synchronisent sur le current du primary, les autres écrans peuvent voir leurs fenêtres basculer.

## Inspection disque

```bash
# Voir l'arborescence persistance per-display
ls -la ~/.config/roadies/displays/

# Voir le current d'un écran spécifique
cat ~/.config/roadies/displays/<UUID>/current.toml

# Voir les fenêtres assignées à un desktop d'un display
cat ~/.config/roadies/displays/<UUID>/desktops/2/state.toml
```

## Migration depuis V2

Aucune action requise. Au premier boot V3 :
- L'ancien `~/.config/roadies/desktops/` est déplacé sous `~/.config/roadies/displays/<primaryUUID>/desktops/`.
- Le mode reste `global` par défaut.
- Le comportement est strictement identique à V2.

## Debug

```bash
# Voir le mode actuel
roadie desktop list --json | jq .data.mode

# Suivre les events de focus avec display_id
roadie events --follow --filter desktop_changed
```
