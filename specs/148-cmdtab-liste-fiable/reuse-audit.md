# Réutilisation148

Propriétaires : readerSnapshot conserve son refus d'un relevé invalidé ; WindowSwitcherService.load est le seul point d'acquisition pour ouverture et rechargement. WindowSwitcherController garde sa session, ses pas en attente et sa validation au relâchement. WindowSwitcherPanel dispose déjà de showLoading et du statut central.

Correction visée : réutiliser la reprise bornée existante du reload dans le service commun, sans nouveau cache, registre, minuteur global, observateur, commande CLI ni préférence. Une indisponibilité ne doit pas construire un modèle vide. Une vraie liste vide reste valide et n'est pas relue inutilement. Après épuisement, afficher une indisponibilité explicite ; ne pas utiliser un relevé ancien ou élargir les filtres.

Les tests réutilisent powerDisplay/powerWindow et une petite doublure du fournisseur pour invalider un relevé en cours. La fixture native et les sources des sondes restent hors Git. Complexité par essai O(w), au plus quatre essais, AX hors MainActor ; pas de boucle au repos.
