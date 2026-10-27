# Recherche 092 - Vue Grille

## R1 Sources des tuiles
Relevé : System Settings Explorer `inputtype` 1, `inputfile` « explore.sh » (zsh, sortie JSON avec
`preselect` et `items`) ; Thumbnail Navigation `inputtype` 0 après une brique JSON qui passe `arg`.
Aide d'Alfred (alfredapp.com/help/workflows/user-interface/grid/, lue le 27 octobre 2026) : « Object
Input » (liste de chemins ou JSON) et « Script Source » (JSON au format Script Filter, lancé une fois,
filtré ensuite comme « Word matching - Any order », `rerun` ignoré, clé `preselect`). Décision :
0 = argument reçu, 1 = script du dossier ; toute autre valeur est une brique manquante nommée
`userinterface.grid:inputtype:N`. Le script de source est un fichier exécutable : lancé comme un
script externe (type 8, `AlfredScriptRunner`), dossier du workflow, mêmes variables.

## R2 Passage du moteur à la barre
Le moteur ne connaît pas la barre ; il a déjà `showBar(_:)` (barre rouverte sur un texte). Décision :
un effet `showGrid(AlfredGridView)` ; l'effet réel garde la vue en attente dans le contrôleur et
rouvre la barre (`targets.search`) ; le contexte du lanceur la reçoit et la barre s'ouvre en grille.
La vue porte une entrée `AlfredEntry` de genre `.grid` dont `objectUID` est l'`uid` de la grille :
Retour réutilise `confirmWorkflow` → `finishWorkflow` → `runWorkflow` → `engine.run(from: grille)`,
qui suit les flèches de la grille avec le modificateur tenu (research R6 de la 088). Aucun nouveau
chemin d'exécution.

## R3 Disposition
`SearchBarLayout` sert le dessin et le clic avec `suggestionRows` (rectangles) et `firstVisible`.
Décision : `makeGrid(bounds:count:columns:selected:…)` rend un rectangle par tuile visible, rangée
par rangée, et `firstVisible` = première tuile de la première rangée montrée ; le clic et ⌘1-9
fonctionnent sans changement. Largeur de la barre (640 points au plus) ; tuile carrée de
largeur/colonnes, bornée à 140 points ; titre sous l'image ; pied d'une ligne si un texte va en pied.

## R4 Touches
Dans la grille, ← et → déplacent la sélection (choix de l'utilisateur : Tab suffit pour les verbes).
Le champ reçoit `gridColumns` comme `pickModifier` : sans modificateur, ← → rendent `.move(-1)` /
`.move(1)` ; ↑ ↓ restent `.previous` / `.next`, que la barre traduit en ± colonnes. Hors grille, rien
ne change. Les espaceurs (titre vide, `valid: false`, sans icône) sont sautés ; une flèche qui sort de
la grille ne bouge pas.

## R5 Aspect des images
`imageaspect` relevé : 0 (System Settings Explorer), 2 (Thumbnail Navigation) ; valeurs non
documentées. Décision : image ajustée sans déformation dans la tuile, quel que soit l'aspect ;
noté en limite.

## R6 Surcharge `config`
Thumbnail Navigation et System Settings Explorer règlent `columncount` par une brique JSON
(`{"alfredworkflow": {"config": {"columncount": "{var:gridCols}"}}}`). `AlfredRunScriptOutput.parse`
lit déjà `config` ; le moteur l'ignorait. Décision : `Step.next` porte la surcharge, appliquée à la
configuration de l'objet suivant pour ce passage seulement (valeurs JSON converties en `PlistValue`).

## R7 Déclencheur sur une brique
Alfred 5.5 : `inboundconfig.externalid` sur une brique quelconque. System Settings Explorer : la
catégorie appelle `listSettings`, porté par sa brique JSON. Corpus : 4 objets dans 4 workflows.
Décision : `AlfredObject.externalID` lu au chargement ; `externalTrigger` cherche d'abord un
`trigger.external`, puis une brique de cet `externalid`. Quand la cible n'est pas un déclencheur, le
moteur exécute la brique elle-même (comme `start`) au lieu de suivre ses flèches.

## R8 Fichiers images
Liste de fichiers : extension d'image (png, jpg, jpeg, gif, heic, tiff, webp, bmp) → icône `.image`
(contenu) ; autre → `.fileIcon` (icône du Finder) ; `isFile` et `quickLookURL` renseignés.
