# OmniWM : bureaux étendus et vue d’ensemble

Analyse du 30 octobre 2026. Version publiée v0.7.6, commit 3c0783954604eaa9110d0bdb61fa29f953e738ee.

## Conclusion

L’intérêt central est la continuité spatiale : le bureau garde une disposition logique, l’écran en montre une portion et la vue d’ensemble projette les mêmes rectangles à une autre échelle. Un bureau peut utiliser Niri et dépasser la largeur de l’écran ; un autre reste compact en Dwindle.

Le ruban conserve l’ordre et les proportions des conteneurs. La vue d’ensemble n’est pas une collection de cartes normalisées. Elle conserve les formes, avec zoom et défilement quand tout ne tient pas.

## Mécanismes vérifiés

### 1. Un moteur différent pour chaque bureau

Un bureau peut utiliser le ruban Niri, un autre le découpage Dwindle. Le choix appartient au bureau, avec une valeur par défaut possible. Changer de bureau change donc aussi la manière de travailler.

Sources : [Choix du moteur par bureau](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Config/WorkspaceConfig.swift).

### 2. Le bureau dépasse l’écran, dans une direction

En Niri, les conteneurs se suivent sur un ruban. Sur une disposition horizontale, ils forment des colonnes ; en orientation verticale, le modèle tourne en rangées. Chaque conteneur peut montrer plusieurs fenêtres empilées ou une seule fenêtre à la fois par onglets.

Sources : [Colonnes, tailles et groupes](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/NiriContainer.swift), [Géométrie destinée à la vue d’ensemble](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/NiriOverviewSnapshot.swift).

### 3. L’écran montre une portion de ce bureau

La disposition logique et la portion visible sont deux états séparés. Aller vers une fenêtre déplace la vue pour la montrer. Chaque bureau garde son état de vue. Le ruban est une géométrie virtuelle ; macOS continue à déplacer de vraies fenêtres sur les écrans physiques.

Sources : [Position de la vue](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/ViewportState.swift), [Géométrie destinée à la vue d’ensemble](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/NiriOverviewSnapshot.swift), [Retour de la vue d’ensemble au bureau](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/NiriLayoutHandler+OverviewViewport.swift).

### 4. Overview conserve la forme, les proportions et les groupes

Le moteur fournit ses propres rectangles au rendu. Un bureau BSP reste compact. Un bureau Niri conserve son étendue et ses colonnes. Les bandes restent zoomables et défilables : un ruban très long peut dépasser aussi de la vue d’ensemble.

Sources : [Géométrie destinée à la vue d’ensemble](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/NiriOverviewSnapshot.swift), [Projection de cette géométrie](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Overview/OverviewLayoutGeometry+NiriProjection.swift), [Projection des bureaux classiques](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Overview/OverviewLayoutGeometry+GenericPreview.swift), [Zoom et bandes de bureaux](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Overview/OverviewLayoutGeometry.swift), [Tests des formes et du débordement](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Tests/OmniWMTests/OverviewLayoutCalculatorTests.swift).

### 5. La vue d’ensemble est un lieu où agir

On peut sélectionner une fenêtre, la déplacer vers un autre bureau et viser une insertion dans un ruban. Les modifications retournent dans le même modèle de disposition. Déplacer la vue dans Overview peut aussi modifier la portion du bureau retrouvée ensuite.

Sources : [Retour de la vue d’ensemble au bureau](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Controller/NiriLayoutHandler+OverviewViewport.swift), [Tests des formes et du débordement](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Tests/OmniWMTests/OverviewLayoutCalculatorTests.swift), [Tests de conservation de la vue](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Tests/OmniWMTests/OverviewViewportCommitTests.swift).

### 6. Les gestes suivent le modèle

Le défilement propose soit un arrêt aligné sur une colonne, soit une inertie libre. Le regroupement agit sur les colonnes ; le BSP agit sur un arbre de divisions. L’ouverture d’Overview tient aussi compte du mouvement du geste.

Sources : [Ajout d’une fenêtre en BSP](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Dwindle/DwindleLayoutEngine+WindowAdmission.swift), [Regrouper et extraire en Niri](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/NiriLayoutEngine+ColumnConsumption.swift), [Deux styles de défilement](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Config/TrackpadScrollStyle.swift), [Transition d’Overview](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Overview/OverviewNativeTransition.swift).

### 7. Les largeurs ne sont pas toujours immuables

Il faut nuancer l’idée « rien ne se redimensionne ». Quand il y a peu de conteneurs, OmniWM peut remplir l’espace libre de façon proportionnelle. Une taille choisie manuellement reçoit un traitement spécifique. Le moteur ne se résume donc pas à une rangée de rectangles fixes.

Sources : [Remplissage automatique](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/Sources/OmniWM/Core/Layout/Niri/NiriLayoutEngine+PrimarySpanFit.swift).

### 8. La gestion des écrans a un coût de configuration

Le guide recommande une carte macOS en escalier pour le placement technique et une seconde carte OmniWM qui représente le bureau physique. Cette séparation sert au routage des mouvements. Elle demande plus de réglages qu’un simple outil de placement.

Sources : [Topologie des écrans](https://github.com/OmniNull/OmniWM/blob/3c0783954604eaa9110d0bdb61fa29f953e738ee/website/src/content/docs/guides/multi-monitor.md).

## Correspondance avec Roadie

OmniWM : écran → workspace → colonnes ou arbre → fenêtres.

Roadie : écran → bureau → stage → fenêtres.

Le workspace OmniWM correspond plutôt à la stage Roadie. Roadie possède déjà un mode par stage. Le manque porte sur le moteur défilant, son état de vue et sa représentation spatiale. La vue d’ensemble actuelle compose une grille de cartes de format unique et affiche les stages dans les légendes.

- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieStages/RoadieState.swift : StageState possède déjà un mode de disposition. Le choix par activité existe donc dans le modèle.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/OverviewModel.swift : OverviewLayout compose une grille de cartes au format unique ; les stages sont identifiées dans leurs légendes.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieCore/WindowManagementMode.swift : Les moteurs actuels sont BSP, arbre BSP persistant, masterStack et flottant, avec un alias historique.

## Direction proposée pour Roadie

1. Ajouter une présentation spatiale fidèle aux dispositions existantes, sans supprimer les présentations actuelles.
2. Concevoir une géométrie logique étendue et une position de vue par stage.
3. Ajouter un moteur à colonnes, avec groupes et onglets.
4. Utiliser la même géométrie pour le bureau, les cibles de déplacement et la vue d’ensemble.
5. Relier rappel d’une fenêtre, barre et zones de clics à la portion de ruban correcte.
6. Valider ensuite gestes, inertie et transitions sur plusieurs écrans.

Un choix au niveau du bureau pourrait servir de défaut à ses stages ; cela reste une proposition de conception. Aucune spécification ni implémentation lancée.

## Nuances et limites

Les largeurs peuvent varier avec le remplissage automatique. Un ruban très long peut déborder de la vue d’ensemble. Les fenêtres des Spaces natifs inactifs ne sont pas tuilées. Le guide multi-écran sépare une carte technique macOS en escalier et une carte de routage physique. Les appartenances aux scratchpads ne survivent pas au processus ; la restauration Dwindle possède des limites documentées.

Documentation et code de v0.7.6 étudiés. La documentation en ligne a pu évoluer après cette version. Lecture ciblée, pas audit complet. Tests lus, non exécutés. Aucun essai de l’application native ni benchmark. La démonstration web a été manipulée : la sélection de Safari décale le ruban, sans modifier les largeurs affichées. Ce fait ne prouve pas la qualité du moteur natif.

Le schéma HTML est une explication originale à données fictives. Il ne reproduit ni le code ni tous les comportements d’OmniWM. Il utilise des largeurs fixes et une échelle commune pour rendre les trois formes visibles.

## Livrables

/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/analyses/2026-10-30-omniwm/rapport.html

/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/docs/analyses/2026-10-30-omniwm/sources.json
