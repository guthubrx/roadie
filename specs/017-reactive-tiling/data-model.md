# Modèle de données : Tiling réactif façon yabai

## Arbre de disposition (existant, `BSPTree`)

- Par stage : `PersistentStage.bspTree` dans `~/.roadies/stages.json`.
- `empty | leaf(WindowID) | split(orientation, ratio, first, second)`, ratio dans [0,05 ; 0,95].
- **Change** :
  - fait foi pour les modes à arbre (R2) ;
  - le sens de coupe d'une insertion suit la feuille (R3) ;
  - les feuilles des membres absents mais encore en grâce sont conservées, et ignorées au placement (R13).
- **Invariant** : chaque feuille correspond à un membre de la stage (vivant, ou absent mais en grâce). Une fenêtre n'apparaît qu'une seule fois dans tous les arbres d'un écran et d'un bureau.

## Mode de stage (existant, `WindowManagementMode`)

- Valeurs persistées acceptées en lecture : `bsp`, `mutableBsp`, `yabai`, `spatialBsp`, `masterStack`, `float`.
- **Change** : `mutableBsp` et `yabai` sont lus comme `spatialBsp`, et l'écriture enregistre `spatialBsp` (R1).
- **Migration** : la première fois qu'une stage migrée a des membres et un arbre vide ou périmé, elle reçoit `BSPTree.inferred(from:in:)`. Une copie `stages.json.pre-017` est faite avant la première écriture migrée.

## Frame écrite (nouveau, en mémoire seulement)

`WrittenFrame { requested, readBack?, accepted?, writtenAt }`, indexé par identifiant de fenêtre.
- Écrite par l'écrivain AX à chaque placement.
- Lue par le maintainer, qui classe chaque frame observée en écho, réponse de l'application ou geste manuel (R6).
- Oubliée à la destruction de la fenêtre.
- Aucune persistance : un redémarrage repart d'un registre vide, et la première passe pose l'arbre.

## Taille minimale observée (nouveau, en mémoire)

`[WindowID: CGSize]`, remplie au premier refus. Elle sert à ajuster une seule fois le ratio du split parent (R4). Elle est oubliée à la destruction de la fenêtre.

## Signature de fichier d'état (nouveau, en mémoire)

`(mtimeNs, size, inode)` par chemin de fichier JSON, avec la valeur décodée associée (R10). Elle est invalidée dès que la signature sur le disque diffère.

## Épisode de placement (nouveau, dans le journal)

`episodeId = "ep_<epoch ms>"`. Il est ouvert par une cause : événement AX, commande, glisser-déposer, échéance interne ou filet périodique. Il est porté par tous les événements émis jusqu'à la cause suivante (R14).

## Garde de transition de bureau (nouveau, en mémoire)

Par scope : `openedAt` et `reason` (sortie du plein écran natif, retour d'un membre manquant). Elle est fermée par `activeSpaceDidChange`, par une frame stable entre deux lectures, ou par le plafond de 1,5 s (R7).
