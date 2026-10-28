# Session 109 : supprimer une stage depuis le rail

## Besoin

L'utilisateur a des stages nommées et des stages anonymes qu'il ne veut plus voir. Il veut les
supprimer par un clic droit sur leur carte du rail. Pour le moment, seule une stage vide se supprime.

Constat du 28 octobre 2026 : l'écran actif gardait 17 stages, dont des restes de reconnexion
(`8-restored-2`, `6-recovered-2`, …). Certains s'affichaient comme des stages nommées vides
(« Stage 7 », « Stage 8 »). `roadie stage delete` existait, mais seulement pour l'écran actif, et
refusait une stage qui gardait en mémoire une fenêtre fermée.

## Règle

Une stage se supprime quand elle est :

- inactive (la stage affichée reste) ;
- non parquée (une stage d'un écran absent attend son retour) ;
- sans fenêtre représentée dans le rail. Une fenêtre fermée, ou absente au-delà de la grâce de
  15 secondes du rail, ne compte pas : elle part avec la stage.

La suppression retire la stage de l'état persistant de son écran et de son bureau. Elle disparaît
donc partout : rail, vue d'ensemble, sélecteur, destinations.

## Interface

Menu du clic droit d'une carte, après « Envoyer la stage vers écran » : « Supprimer la stage ».
Quand la règle refuse, l'entrée est grisée et donne la raison : « stage active », « contient des
fenêtres », « écran absent ». Si une fenêtre arrive entre l'ouverture du menu et le choix, la
commande refuse et le son d'alerte retentit.

## Commande

`roadie stage delete ID` suit la même règle sur l'écran actif. Le rail passe l'écran cliqué.

## Hors périmètre

- Supprimer une stage qui contient des fenêtres (choix de leur destination).
- Supprimer la stage active (il faudrait d'abord en afficher une autre).
- Nettoyage groupé des restes de reconnexion.
