# Plan

## Diagnostic réutilisé

Les événements réels du 21 octobre à 05:57:16Z et 05:59:07Z confirment deux
affectations sur l'écran externe, stages 2 et 5. Ils n'enregistrent pas le point
de dépôt : ils ne prouvent pas à eux seuls la mauvaise carte visée.

RailPanel.windowDropTarget choisit emptyStageIDs.first hors carte, sans rang de
stage. RailController ne bloque la reconstruction que pour le glisser droit de
stage. StagePresentationOrder partitionne automatiquement occupées puis vides.
Ces comportements sont à tester avant correction, sans prétendre que les trois
expliquent chacun les deux gestes réels.

## Implémentation

Réutiliser les cadres AppKit des cartes et leurs conversions après défilement.
Distinguer carte et interstice. Porter le rang de la stage vide cible dans
RailWindowDropTarget puis dans la transaction existante StageCommandService.assign.
Figer les reconstructions dès la prise d'une vignette, y compris une tâche de
lecture déjà lancée, puis rafraîchir après le dépôt ou l'annulation.
Montrer une destination sobre et transparente aux clics, sans trait bleu.
Ajouter aux événements du dépôt les coordonnées et le type de cible.

Tester la sélection, le rang persisté et les autres membres dans un et deux scopes,
les interstices, le défilement, les cartes de tailles différentes et la libération
de la garde. Reprendre la politique de tri après réponse de l'utilisateur.
Conserver une complexité linéaire dans le nombre de cartes, sans relevé AX par
mouvement. Aucun nouveau paquet ou moteur de thème.
