# Contract: CLI stage move-to-display

## Command

```bash
roadie stage move-to-display TARGET [--follow|--no-follow]
```

## TARGET

`TARGET` accepte :

- index visible d'ecran : `1`, `2`, `3` ;
- direction depuis l'ecran courant : `left`, `right`, `up`, `down`.

Exemples :

```bash
roadie stage move-to-display 2
roadie stage move-to-display right
roadie stage move-to-display left --no-follow
roadie stage move-to-display 1 --follow
```

## Semantics

- Sans flag, la commande utilise `[focus].stage_move_follows_focus`.
- `--follow` force le focus a suivre la stage deplacee.
- `--no-follow` garde le contexte actif sur l'ecran source.
- Si `TARGET` designe l'ecran courant, la commande retourne un no-op explicite.
- Si `TARGET` n'existe pas, la commande ne modifie pas le state.
- Si `TARGET` directionnel est ambigu ou absent, la commande ne modifie pas le state.

## Success Output

Format texte stable pour usage humain :

```text
stage move-to-display: moved stage=3 target=2 follow=false windows=3 failed=0
```

## Failure Output

```text
stage move-to-display: invalid target=unknown
stage move-to-display: target is current display
stage move-to-display: partial stage=3 target=2 follow=true windows=2 failed=1
```

## Exit Behavior

- `0` : success ou no-op explicite sans corruption.
- non-zero : erreur de parsing, cible invalide, daemon indisponible, echec de mutation state.

## Compatibility

La forme existante `roadie stage move-to-display N` reste valide. Les raccourcis BTT existants qui appellent cette forme ne doivent pas changer de comportement sauf si la configuration globale de follow change.
