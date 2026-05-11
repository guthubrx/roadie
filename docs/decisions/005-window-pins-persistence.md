# 005 - Persistance des pins de fenêtres

## Statut

Accepté.

## Contexte

Roadie doit permettre de garder une fenêtre visible au-delà de sa stage d'origine sans la dupliquer dans plusieurs stages. Les bugs récents de layout et de bordure rendent risquée toute solution qui modifierait l'arbre de layout actif à chaque changement de stage ou de desktop.

## Décision

Les pins de fenêtres sont stockés dans `PersistentStageState.windowPins`. Chaque pin conserve un `homeScope` unique et un scope de visibilité (`desktop` ou `all_desktops`). La fenêtre reste membre d'une seule stage, mais elle est exclue du layout automatique tant que le pin existe.

## Conséquences positives

- Les fichiers `stages.json` existants restent compatibles : l'absence de `windowPins` vaut liste vide.
- Une fenêtre pinée ne peut pas être dupliquée dans plusieurs stages.
- Le retrait du pin peut remettre la fenêtre dans un contexte unique.
- Les déplacements explicites de fenêtre ou de stage mettent à jour le `homeScope` du pin.

## Conséquences négatives

- Le maintainer doit traiter explicitement la restauration d'une fenêtre pinée cachée.
- Les pins restent liés aux IDs de fenêtres live ; une fenêtre fermée supprime son pin au prochain refresh.
- Le pin global multi-écran n'est pas supporté dans cette version.
