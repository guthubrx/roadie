# Plan

Réutiliser la lecture AX fraîche déjà fournie au mainteneur. Avant le plan d'un groupe
à arbre, attendre lorsqu'une fenêtre sans preuve d'écriture reste sur un autre écran
et ne peut pas être relue. Ne pas réduire les voisines pendant cette attente.

La passe de sécurité existante observe la disponibilité : aucun nouveau moteur,
aucune boucle rapide, aucun réglage supplémentaire. À la première lecture valide,
le plan ordinaire reprend. Les échecs de résolution antérieurs à une écriture AX
ne doivent pas bloquer cette reprise ; le registre garde la limite des écritures réelles.

Valider la régression avant/après avec deux écrans, une fenêtre initialement illisible,
des coordonnées négatives, un autre groupe actif, puis disponibilité ou disparition.
Conserver les tests de refus, budget, gestes, fermeture et plein écran existants.

La livraison combine les sources déjà installées avec ce correctif. Ne pas installer
le seul main : il manque encore le travail parallèle déjà utilisé par l'application.
