# Contract: configuration focus stage move

## TOML

```toml
[focus]
stage_move_follows_focus = true
```

## Default

Si la cle est absente, Roadie se comporte comme aujourd'hui pour la majorite des utilisateurs : le focus suit la stage deplacee.

```toml
[focus]
stage_move_follows_focus = false
```

Configuration demandee par l'utilisateur courant : la stage part vers l'autre ecran, mais le focus reste sur l'ecran source.

## Validation

- Type attendu : booleen.
- Valeurs valides : `true`, `false`.
- Une valeur invalide doit etre rejetee par la validation config, sans appliquer partiellement le fichier.

## Interaction avec les flags CLI

Priorite effective :

1. flag CLI `--follow` ou `--no-follow` ;
2. config `[focus].stage_move_follows_focus` ;
3. defaut `true`.

## Non-goals

- Cette cle ne remplace pas `assign_follows_focus`.
- Cette cle ne change pas le comportement de `stage switch`, `stage assign`, `focus left/right/up/down` ou du focus follows mouse.
