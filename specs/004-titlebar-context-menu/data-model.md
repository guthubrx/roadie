# Modèle de Données : Menu Contextuel de Barre de Titre

## TitlebarContextMenuSettings

Preferences utilisateur experimentales.

| Champ | Type | Défaut | Validation |
|-------|------|---------|------------|
| `enabled` | Bool | `false` | Aucun menu si `false` |
| `height` | Number | `36` | Entre 12 et 96 px |
| `leading_exclusion` | Number | `84` | Entre 0 et 240 px |
| `trailing_exclusion` | Number | `16` | Entre 0 et 240 px |
| `managed_windows_only` | Bool | `true` | Si `true`, seules les fenetres avec scope Roadie sont eligibles |
| `tile_candidates_only` | Bool | `true` | Si `true`, exclut popups/dialogues/non-tile candidates |
| `include_stage_destinations` | Bool | `true` | Controle le sous-menu stage |
| `include_desktop_destinations` | Bool | `true` | Controle le sous-menu desktop |
| `include_display_destinations` | Bool | `true` | Controle le sous-menu ecran |

## TitlebarHitTest

Resultat pur de detection pour un clic droit.

| Champ | Type | Notes |
|-------|------|-------|
| `screen_point` | Point | Position du clic en coordonnees ecran |
| `window_id` | WindowID? | Fenetre sous le curseur si trouvee |
| `is_eligible` | Bool | `true` seulement si toutes les regles passent |
| `reason` | String | `disabled`, `no_window`, `not_managed`, `not_titlebar`, `excluded_margin`, `transient`, `eligible` |

## WindowContextAction

Action choisie dans le menu.

| Champ | Type | Notes |
|-------|------|-------|
| `window_id` | WindowID | Fenetre cible du menu |
| `kind` | Enum | `stage`, `desktop`, `display` |
| `target_id` | String | ID destination |
| `source_scope` | StageScope? | Contexte connu au moment de l'ouverture |

## WindowDestination

Destination affichable dans un menu.

| Champ | Type | Notes |
|-------|------|-------|
| `kind` | Enum | `stage`, `desktop`, `display` |
| `id` | String | Identifiant stable Roadie |
| `label` | String | Libelle utilisateur |
| `is_current` | Bool | Destination courante de la fenetre |
| `is_available` | Bool | False si destination disparue ou invalide |

## Transitions d'État

1. `disabled` -> aucun menu, clic laisse a l'application.
2. `right_click` -> `TitlebarHitTest`.
3. `eligible` -> menu construit a partir des destinations courantes.
4. `action_selected` -> validation que fenetre et destination existent encore.
5. `success` -> action executee et evenement journalise.
6. `ignored` ou `failure` -> aucun changement de contexte fenetre.
