# 015 - Relevés des lecteurs au repos

Date : 2026-10-18. Statut : accepté, session 048.
Amende la clause « Conserver les durées de validité existantes » de
`docs/decisions/013-acquisition-lecteurs-asynchrone.md`.

## Contexte

Au repos, le daemon consommait 11,45 % d'un cœur (mesure du 18 octobre,
`specs/048-consommation-repos/mesures/avant.json`). Environ 460 des 539 échantillons
de relevé AX complet venaient des lecteurs : bordure (120 ms), poignées (150 ms),
rail (1 s). Leur relevé n'était réutilisable que 150 ms, même sans aucun changement.
L'ADR 013 refusait d'allonger cette durée, car un cache plus long masque des
changements réels.

## Décision

Un changement réel passe par l'ordonnanceur du tiler : événements AX, NSWorkspace,
écrans, réveil, commandes. Chaque demande hors filet périodique incrémente une
génération d'observation, rangée avec le cache du fichier d'état.

Un lecteur réutilise le dernier relevé publié au-delà de 150 ms seulement si :
- aucune génération nouvelle n'est apparue depuis le départ de ce relevé ;
- son âge reste sous l'intervalle du filet du tiler (2 s par défaut) ;
- l'état persisté et la configuration n'ont pas changé.

Cette réutilisation n'est activée que par le tiler, quand les événements en direct
sont actifs. Un lecteur sans ordonnanceur (mode modulaire, `--no-live-events`)
garde la règle des 150 ms. Les commandes gardent la règle des 150 ms.

## Conséquences

- Positive : au repos, les lecteurs réutilisent le relevé du tiler au lieu de relever
  plusieurs fois par seconde.
- Négative : un changement sans notification (titre, application sans observateur AX,
  permission) peut être vu par un lecteur jusqu'à 2 s plus tard. Le filet du tiler a
  déjà ce délai de rattrapage. Cela vaut aussi pour la cible du focus qui suit la souris :
  un cadre changé sans notification peut être pris en compte jusqu'à 2 s plus tard.
- Vignettes du rail : une fenêtre ScreenCaptureKit déjà connue est réutilisée ; une
  capture vide (fenêtre réduite ou protégée) la garde en cache, car une nouvelle
  énumération ne changerait pas le résultat.
- La génération est lue au départ du relevé, jamais à sa publication : un événement
  survenu pendant l'acquisition rend le relevé non réutilisable.
