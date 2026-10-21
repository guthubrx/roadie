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
Distinguer carte et interstice. Porter l'intention « avant cet identifiant » ou
« à la fin » dans RailWindowDropTarget puis dans la transaction existante
StageCommandService.assign. Résoudre le rang sous le verrou d'affectation : un
test avec une stage ajoutée en arrière-plan échoue avec le rang numérique figé.
Si le slot est devenu occupé ou l'ancre a disparu, refuser sans mutation.
Figer les reconstructions dès la prise d'une vignette, y compris une tâche de
lecture déjà lancée, puis rafraîchir après le dépôt ou l'annulation.
Montrer une destination sobre et transparente aux clics, sans trait bleu.
Ajouter aux événements du dépôt les coordonnées et le type de cible.

Tester la sélection, le rang persisté et les autres membres dans un et deux scopes,
les interstices, le défilement, les cartes de tailles différentes et la libération
de la garde. L'utilisateur confirme que son ordre prévaut : supprimer la partition
occupées/vides de la projection et du fantôme, conserver la liste défilable.
Conserver une complexité linéaire dans le nombre de cartes, sans relevé AX par
mouvement. Aucun nouveau paquet ou moteur de thème.

## Complément après essai utilisateur

Diagnostic initial de géométrie à écarter si le test de reconstructions successives
conserve les écarts. La chronologie et la garde de `StageCardView.drawEmpty` indiquent
une carte nommée devenue entièrement transparente après le fondu. Réutiliser le cadre
de son aperçu pour un emplacement vide toujours visible, sa police configurée et un
texte tronqué. Tester les quatre rendus, libellés expirés et désactivés. Les libellés
des stages occupées conservent leur temporisation. Pas de nouvelle lecture AX.
