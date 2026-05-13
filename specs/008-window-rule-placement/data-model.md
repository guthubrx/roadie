# Data Model: Placement des fenêtres par règle

## WindowRule

Règle utilisateur existante dans `[[rules]]`.

Champs concernés :
- `id` : identifiant unique de règle.
- `priority` : priorité de traitement.
- `match` : critères app, titre, rôle, subrole, contexte.
- `action` : actions à appliquer.

## RuleAction

Action enrichie :
- `assign_stage` : stage cible par ID ou nom.
- `assign_desktop` : desktop cible existant, conservé.
- `assign_display` : écran cible par ID ou nom.
- `follow` : booléen optionnel ; `false` par défaut.

Validation :
- `assign_display` peut être absent.
- `assign_stage` peut être absent si la règle ne cible que l'écran.
- `follow` ne doit pas changer le comportement des anciennes règles.

## PlacementDestination

Destination résolue à l'exécution :
- `displayID`
- `desktopID`
- `stageID`

États :
- `applied` : fenêtre déplacée vers la destination.
- `already_satisfied` : fenêtre déjà dans la bonne destination.
- `deferred` : destination impossible maintenant, typiquement écran absent.
- `skipped` : règle non applicable ou fenêtre non gérée.

## PersistentStageState

État existant qui porte les scopes display/desktop/stage. La feature ajoute ou met à jour des membres de stage, sans changer le format principal de l'état.
