# Quickstart : Pins de Fenêtres

## Préconditions

1. Construire Roadie.
2. Lancer `roadied`.
3. Activer le menu contextuel de barre de titre si nécessaire :

```toml
[experimental.titlebar_context_menu]
enabled = true
height = 36
leading_exclusion = 84
trailing_exclusion = 16
managed_windows_only = true
tile_candidates_only = true
include_stage_destinations = true
include_desktop_destinations = true
include_display_destinations = true
```

## Scénario 1 : pin sur le desktop courant

1. Ouvrir deux stages dans le même desktop.
2. Ouvrir une fenêtre utilisateur normale.
3. Clic droit dans la barre de titre.
4. Choisir `Fenêtre` -> `Pin sur ce desktop`.
5. Changer de stage plusieurs fois.

Résultat attendu : la fenêtre reste visible et ne force pas les autres fenêtres à bouger.

## Scénario 2 : pin sur tous les desktops du même écran

1. Ouvrir au moins deux desktops Roadie sur le même écran.
2. Pinner une fenêtre avec `Pin sur tous les desktops`.
3. Changer de desktop et de stage.

Résultat attendu : la fenêtre reste visible sur cet écran, garde sa position, et ne devient pas un tile dans les layouts actifs.

## Scénario 3 : retrait du pin

1. Ouvrir le menu de barre de titre sur une fenêtre pinée.
2. Choisir `Retirer le pin`.
3. Changer de stage et de desktop.

Résultat attendu : la fenêtre redevient visible uniquement dans son contexte normal.

## Régressions à vérifier

- Une fenêtre non pinée garde le comportement stage/desktop actuel.
- Une fenêtre exclue du tiling ne devient pas tileable parce qu'elle est pinée.
- Les popups, dialogues de sauvegarde, panneaux système et sheets ne proposent pas de pin.
- Les bordures suivent toujours le focus d'une fenêtre non pinée.
- Un changement de stage via `Alt-1`, `Alt-2`, etc. ne provoque pas de flash ou de déplacement des fenêtres non pinées.
