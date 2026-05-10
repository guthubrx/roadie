# Contract: navrail context menu stage display move

## Trigger

L'utilisateur fait un clic droit sur une carte de stage dans le navrail.

## Menu

Si plusieurs ecrans sont disponibles :

```text
Envoyer vers
  LG HDR 4K
  Built-in Retina Display
```

Regles :

- ne pas afficher l'ecran qui contient deja la stage ;
- afficher les noms utilisateur des ecrans si disponibles ;
- conserver un ordre stable equivalent aux index visibles Roadie ;
- si un seul ecran existe, masquer l'entree ou l'afficher desactivee.

## Action

Selectionner une cible declenche :

```swift
moveStageToDisplay(
  stageID: clickedStageID,
  sourceDisplayID: railDisplayID,
  targetDisplayID: selectedDisplayID,
  followFocus: config.focus.stageMoveFollowsFocus
)
```

La stage cliquee peut etre inactive. Elle ne doit pas etre activee seulement pour pouvoir etre deplacee.

## Result UX

- Succes : la carte disparait du rail source et devient disponible sur le rail cible.
- No-follow : le rail source garde son contexte actif si possible.
- Follow : le contexte actif passe sur l'ecran cible.
- Echec : aucune stage ne disparait ; un message diagnostic est logge et la commande retourne un resultat clair.

## Non-goals

- Drag and drop de carte de stage entre rails.
- Menu de renommage/reorder de stage.
- Creation automatique d'un nouvel ecran logique.
