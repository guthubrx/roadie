# Implémentation

## Rendu

RailPanel transmet la position de la carte affichée à StageCardView. Le libellé
devient « position — nom ». Numéro et nom passent par le même dessin et la même
opacité ; le minuteur existant contrôle leur apparition et leur disparition.
La carte garde sa géométrie habituelle. Aucun badge ou minuteur supplémentaire.

La branche principale ne contenait pas encore les badges de la session
parallèle. Dans la copie de livraison, son ancien StageCardView est remplacé
par celui de cette session. La hauteur réservée au badge dans RailPanel et
le test qui exigeait un numéro permanent sont retirés. Tous les autres
changements installés sont conservés. Le patch de remplacement est archivé
dans le dossier de validation. Le worktree parallèle reste intact.

## Raccourcis installés

| Geste | Gestionnaire | Action |
|---|---|---|
| Deux appuis sur Alt gauche | BetterTouchTool | Grille interactive de l'écran, durée 15 s |
| Deux appuis sur Alt droite | Karabiner | Libellés du rail, durée 5 s puis fondu de 0,35 s |

Le trigger BTT droit `54EAC784-B5C4-4C1C-AE82-7EE7BEE0B816` lançait
une grille de fenêtre en parallèle de Karabiner. Il est désactivé via
update_trigger, avec les deux indicateurs BTTEnabled et BTTEnabled2 à zéro.
Le trigger gauche `59DBB2A3-52ED-44D8-802A-DC42CADABA11` est conservé.
La configuration Karabiner n'est pas modifiée.

## Vérification avant installation

- Le rendu de l'ancien badge provoque 20 écarts dans les quatre modes testés.
- Le rendu corrigé passe dans les quatre modes : repos, révélation, expiration,
  désactivation et géométrie stable.
- 20 tests ciblés passent, avec la typographie et la récupération au démarrage.
- La suite combinée passe : 1 539 tests dans 165 suites.
- Les deux réglages BTT sont relus après mutation. Le profil Karabiner actif
  conserve un seul double appui Alt droite pour les libellés.
- Une capture de l'écran réel confirme les trois anciens badges avant installation.

## Revue

Le changement de production sur la branche principale ajoute un argument
optionnel au composant existant et préfixe son texte. La position vient de la
même énumération que les cartes. Aucun nom ou identifiant persistant n'est modifié.
Le rendu livré retire le dessin séparé du badge et sa bande réservée.

Minimalisme et responsabilité future : pas de dépendance, de nouvel état,
de boucle ou d'abstraction. Le code se comprend par la règle utilisateur :
numéro et nom apparaissent et disparaissent ensemble. Aucun calcul supplémentaire
de l'ordre des stages. Préfixage linéaire dans la longueur du texte.
