# Modèle de Données : Menu Pin et Repliage

## PinPresentationState

État de présentation associé à une fenêtre pinée.

| Champ | Type | Notes |
|-------|------|-------|
| `windowID` | WindowID | Fenêtre pinée concernée |
| `presentation` | PinPresentationMode | `visible` ou `collapsed` |
| `restoreFrame` | Rect? | Position/taille à restaurer après repliage |
| `proxyFrame` | Rect? | Position/taille du proxy compact |
| `updatedAt` | Date | Diagnostic et résolution d'état ancien |

## PinPresentationMode

Mode d'affichage utilisateur d'un pin.

| Valeur | Comportement |
|--------|--------------|
| `visible` | La vraie fenêtre pinée est visible selon son scope de pin |
| `collapsed` | La vraie fenêtre ne masque plus le contenu dessous; un proxy Roadie reste visible |

## PinPopoverSettings

Réglages utilisateur de l'overlay et du repliage.

| Champ | Type | Défaut attendu | Notes |
|-------|------|----------------|-------|
| `enabled` | Bool | `false` | Active le contrôle visible |
| `show_on_unpinned` | Bool | `true` | Affiche le contrôle sur les fenêtres gérées non pinées pour permettre le pin direct |
| `button_size` | Double | `12.5` | Diamètre approximatif style bouton macOS |
| `button_color` | String | `#0A84FF` | Couleur du bouton |
| `titlebar_height` | Double | `36` | Bande haute de placement probable |
| `leading_exclusion` | Double | `64` | Zone gauche réservée aux boutons natifs |
| `trailing_exclusion` | Double | `16` | Zone droite protégée |
| `collapse_enabled` | Bool | `true` | Autorise l'action Replier |
| `proxy_height` | Double | `28` | Hauteur du proxy replié |
| `proxy_min_width` | Double | `160` | Largeur minimale du proxy |

## PinPopoverPlacement

Résultat pur de placement du bouton.

| Champ | Type | Notes |
|-------|------|-------|
| `windowID` | WindowID | Fenêtre cible |
| `buttonFrame` | Rect? | Cadre du bouton si placement sûr |
| `isSafe` | Bool | `true` si affichable |
| `reason` | String | `eligible`, `disabled`, `not_pinned`, `not_managed`, `not_visible`, `collapsed` |

## CollapsedPinProxy

Représentation visible d'un pin replié.

| Champ | Type | Notes |
|-------|------|-------|
| `windowID` | WindowID | Fenêtre restaurable |
| `title` | String | Titre affiché, tronqué si nécessaire |
| `appName` | String | Nom ou bundle lisible |
| `pinScope` | WindowPinScope | Scope courant du pin |
| `frame` | Rect | Position du proxy |
| `canRestore` | Bool | `false` seulement si la fenêtre live a disparu |

## Transitions d'État

1. `unpinned` -> aucun état de présentation.
2. `pinned.visible` -> `pinned.collapsed` via action "Replier".
3. `pinned.collapsed` -> `pinned.visible` via clic proxy ou action "Restaurer".
4. `pinned.*` -> aucun état de présentation via "Retirer le pin".
5. `pinned.collapsed` -> `pruned` si la fenêtre live disparaît.

## Invariants

- Une fenêtre non pinée peut afficher le contrôle visible si `show_on_unpinned = true`, mais elle ne reçoit aucun état de présentation tant qu'elle n'est pas pinée.
- Un proxy replié ne participe jamais au layout automatique.
- Le repliage conserve un frame de restauration avant de cacher la vraie fenêtre.
- Le bouton, le menu et le proxy sont exclus des snapshots de fenêtres gérées par Roadie.
- Une fenêtre repliée conserve son scope de pin jusqu'à action utilisateur explicite.
