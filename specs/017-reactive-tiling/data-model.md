# Modèle de données : Tiling réactif façon yabai

## Arbre de disposition (existant, `BSPTree`)

- Par stage : `PersistentStage.bspTree` dans `~/.roadies/stages.json`.
- `empty | leaf(WindowID) | split(orientation, ratio, first, second)`, ratio dans [0,05 ; 0,95].
- **Change** :
  - fait foi pour les modes à arbre (R2) ;
  - le sens de coupe d'une insertion suit la feuille (R3) ;
  - les feuilles des membres absents sont gardées pendant la grâce réelle du membre (30 min), et retirées sur destruction confirmée ;
  - les opérations géométriques se font sur l'arbre projeté (A9).
- **Invariant** : chaque feuille correspond à un membre de la stage (vivant, ou absent mais en grâce). Une fenêtre n'apparaît qu'une seule fois dans tous les arbres d'un écran et d'un bureau.

## Mode de stage (existant, `WindowManagementMode`)

- Valeurs persistées acceptées en lecture : `bsp`, `mutableBsp`, `yabai`, `spatialBsp`, `masterStack`, `float`.
- **Change** : le décodage est inchangé. `usesTreeEngine` vaut vrai pour `spatialBsp` et `mutableBsp`. La config lit `mutableBsp` et `yabai` comme `spatialBsp` (A8).
- **Migration** : `StageStore.migrateLegacyTreeModes`, sous un seul verrou :
  1. sauvegarde des octets bruts dans `stages.json.pre-017`, une seule fois ;
  2. passage en `spatialBsp` ;
  3. arbre construit par `BSPTree.inferred`, avec les membres dans l'ordre et un repli ordonné ;
  4. écriture forcée.

## Frame écrite (nouveau, en mémoire seulement)

`WrittenFrame { requested, readBack?, accepted?, writtenAt, layoutVersion, writesInVersion }`, indexé par identifiant de fenêtre.
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

Par écran : `openedAt` et `reason` (sortie du plein écran natif, retour d'un membre manquant). Elle est fermée quand le type du bureau courant de cet écran est « utilisateur » (sonde privée en lecture seule), par repli sur `activeSpaceDidChange` suivi d'une frame stable, ou au plafond de 1,5 s avec `closedBy=timeout` (A5).

## Version de disposition (nouveau, en mémoire)

C'est un compteur par scope. Il augmente à chaque mutation de l'arbre ou du conteneur. Le budget de 2 écritures par fenêtre s'applique pour une même version (A2).

## Session de geste (nouveau, en mémoire)

`{ windowID, startFrame, button, startedAt }`. Elle est ouverte au clic et fermée au relâchement. Elle est tenue par `UserInputActivity` (A4).
