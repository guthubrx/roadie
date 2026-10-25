# Recherche 080

## R1 Ce qui se lit d'une fenêtre
`AXDocument` (077 R6) : fichier pour TextEdit, Aperçu… ; adresse web pour Chrome et les
applications Electron ; rien pour Firefox, Teams, iTerm2. Une fenêtre sans document se rouvre en
nouvelle fenêtre vide de son application (limite assumée et affichée).

## R2 Ordre et attente
Ouvrir les fenêtres une à une : la première fenêtre inconnue du paquet après chaque ouverture est
la bonne (même mécanisme que 074/077). En parallèle, deux fenêtres d'une même application se
confondraient. 10 s au plus par fenêtre.

## R3 Disposition
`BSPTree` est public et codable. Gardé avec des feuilles = rang de la fenêtre dans le projet ;
remis en remplaçant chaque rang par la fenêtre rouverte de même rang, seulement si toutes sont
revenues (sinon la réconciliation garde l'arbre naturel). Écrit par `mutate { setBSPTree }`.

## R4 Où s'exécute l'enregistrement
La lecture AX exige l'autorisation de Roadie : `project save` et `open` passent par le démon
(commande d'exécution), `list` lit le fichier dans la CLI.
