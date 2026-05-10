# Quickstart: Stage Display Move

## 1. Deplacer la stage active par index d'ecran

```bash
roadie stage move-to-display 2
```

Resultat attendu : la stage active quitte l'ecran courant et apparait sur l'ecran 2.

## 2. Deplacer la stage active par direction

```bash
roadie stage move-to-display right
roadie stage move-to-display left
roadie stage move-to-display up
roadie stage move-to-display down
```

Si aucun ecran voisin clair n'existe dans cette direction, Roadie refuse l'action sans modifier les stages.

## 3. Ne pas suivre la stage deplacee

Dans le TOML Roadie :

```toml
[focus]
stage_move_follows_focus = false
```

Puis :

```bash
roadie config reload
roadie stage move-to-display right
```

Resultat attendu : les fenetres de la stage vont sur l'autre ecran, mais le focus reste sur l'ecran source.

## 4. Forcer ponctuellement le comportement

```bash
roadie stage move-to-display right --follow
roadie stage move-to-display right --no-follow
```

Les flags CLI gagnent sur la configuration TOML pour l'action courante.

## 5. Menu contextuel du navrail

1. Ouvrir le navrail.
2. Clic droit sur une carte de stage.
3. Choisir `Envoyer vers`.
4. Selectionner l'ecran cible.

Resultat attendu : la stage selectionnee est deplacee vers l'ecran cible, meme si elle n'etait pas active.

## Validation developpeur

```bash
swift test
roadie stage move-to-display 2 --no-follow
roadie stage move-to-display right --follow
```

Verifier manuellement :

- l'ecran source garde une stage active saine ;
- aucune fenetre ne disparait ;
- les stages existantes sur l'ecran cible ne sont pas fusionnees ;
- le comportement follow/no-follow correspond au TOML ou au flag CLI ;
- le menu rail ne propose pas l'ecran courant comme cible.

## Validation 2026-05-10

- `./scripts/with-xcode swift test --filter StageDisplayMoveTests` : OK, 10 tests passes.
- `./scripts/with-xcode swift test --filter ConfigTests` : OK, 11 tests passes.
- `make build` : OK.
- `swift build --target RoadieDaemonTests` : OK, inclut la compilation de `StageDisplayMoveTests.swift`.
- `swift build --target roadie` : OK.
- `swift build --target roadied` : OK.
- `swift test --filter StageDisplayMoveTests` sans wrapper Xcode : echec au link avant execution des tests avec `ld: unknown option: -no_warn_duplicate_libraries`.
- Scenarios manuels multi-ecran : a executer apres resolution du probleme linker et relance de la nouvelle app.
