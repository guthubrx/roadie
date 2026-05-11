# Modèle de Données : Pins de Fenêtres

## PersistentWindowPin

État persistant d'un pin utilisateur.

| Champ | Type | Notes |
|-------|------|-------|
| `windowID` | WindowID | Identifiant de la fenêtre live au moment du pin |
| `homeScope` | StageScope | Scope d'origine unique de la fenêtre |
| `pinScope` | WindowPinScope | `desktop` ou `all_desktops` |
| `bundleID` | String | Diagnostic et nettoyage humain |
| `title` | String | Diagnostic et menu |
| `lastFrame` | Rect | Position/taille à préserver autant que possible |
| `createdAt` | Date | Audit et diagnostic |
| `updatedAt` | Date | Mise à jour lors d'un changement de scope ou de frame |

## WindowPinScope

Limite de visibilité du pin.

| Valeur | Comportement |
|--------|--------------|
| `desktop` | Visible sur toutes les stages du `homeScope.desktopID`, uniquement sur le `homeScope.displayID` |
| `all_desktops` | Visible sur tous les desktops Roadie du `homeScope.displayID` |

## Pin Visibility Decision

Résultat pur calculé à partir du pin et du contexte actif.

| Champ | Type | Notes |
|-------|------|-------|
| `windowID` | WindowID | Fenêtre concernée |
| `shouldBeVisible` | Bool | Si `true`, le maintainer ne doit pas cacher la fenêtre |
| `effectiveScope` | StageScope? | Scope actif compatible avec le pin, si utile aux diagnostics |
| `homeScope` | StageScope | Scope d'origine stable |
| `reason` | String | `home`, `desktop_pin`, `all_desktops_pin`, `out_of_scope`, `stale` |

## Eligible Pinned Window

Fenêtre que Roadie peut pinner sans danger.

| Condition | Règle |
|-----------|-------|
| Scope Roadie connu | `ScopedWindowSnapshot.scope != nil` |
| Fenêtre utilisateur | La fenêtre passe les règles du menu de barre de titre |
| Non transitoire | Pas de popup, dialogue, sheet, panneau système ou fenêtre non tile candidate si la config du menu l'exclut |
| Pas déjà stale | La fenêtre existe encore au moment de l'action |

## Transitions d'État

1. `unpinned` -> `pinned_desktop` via "Pin sur ce desktop".
2. `unpinned` -> `pinned_all_desktops` via "Pin sur tous les desktops".
3. `pinned_desktop` -> `pinned_all_desktops` via changement de scope.
4. `pinned_all_desktops` -> `pinned_desktop` via changement de scope.
5. `pinned_*` -> `unpinned` via "Retirer le pin".
6. `pinned_*` -> `pruned` quand la fenêtre live disparaît.

## Invariants

- Un `windowID` ne peut avoir qu'un seul `PersistentWindowPin`.
- Un pin ne crée jamais un membre de stage supplémentaire.
- Une fenêtre pinée conserve un `homeScope` unique.
- Une fenêtre pinée est exclue du layout automatique pendant toute la durée du pin.
- Le retrait du pin laisse la fenêtre dans le contexte actif courant ou dans son `homeScope` si le contexte actif est hors scope.
