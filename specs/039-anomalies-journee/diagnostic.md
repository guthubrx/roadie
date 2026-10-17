# Diagnostic du 17 octobre 2026

Période analysée : 00:00–19:26:44, Europe/Paris. 10 834 événements. Archives complètes conservées séparément avec SHA-256.

## Confirmé

- Saturation ponctuelle du fil principal : live_tick jusqu’à 5514 ms, dernier relevé 3088 ms et retard de lancement 11211 ms. Le sample confirme l’attente dans les lectures AX, dont les parcours de panneaux attachés.
- Cache partagé daté avant la production : un scan long épuise la fenêtre de réutilisation avant sa publication.
- Parcours des contrôles attachés même quand aucune fenêtre candidate n’a besoin de cette résolution.

## Comportements constatés, causalité non établie

- 9 redimensionnements reconnus. Aucun événement de retour arrière de la même fenêtre dans les 3 secondes qui suivent. Cela ne prouve pas que tout geste a été reconnu.
- 18 échecs de placement. Notamment Firefox en sortie de plein écran à 13:53 : deux tentatives par génération, puis reprise sur nouvel événement. Pas de boucle sans borne dans cette séquence.
- À 19:24:55, deux positions externes rétablies, tailles inchangées. Pas de redimensionnement reconnu associé. Le fonctionnement prévu du tuilage peut produire ces événements ; le journal seul ne permet pas d’affirmer une perte de geste.
- Une récupération de trois stages à 10:42 après retour de l’écran externe, attendue. 25 changements de stages et 5 déplacements via le rail. Pas de corruption démontrée par ces compteurs.
- Le journal stderr contient une continuation Swift non reprise, sans date ni pile causale. Attribution au lot de vignettes non prouvée ; aucun changement spéculatif.

## Méthode et limites

Les distributions ne portent que sur les événements journalisés, pas sur toutes les passes. Les samples mesurent des piles de temps mural et non une part CPU exacte.
Revue indépendante demandée : Bridget refuse le lancement avec t3_session_unavailable / attestation_transport_unavailable. Aucun agent lancé ni moteur de repli.
Capture native impossible : screencapture retourne could not create image from display. CUA retourne CUA_REPL_ENABLED_SURFACES is required. Aucun geste aveugle.

## Autres causes confirmées après le premier inventaire

- Rail et menu : coordonnées lues sur la souris actuelle pendant un traitement différé. La reproduction native non postée (CGEvent) montre huit erreurs de coordonnées avant correction ; les tests avec coordonnées enregistrées passent, y compris écran supérieur.
- Geste : le test reproduit un redimensionnement 500→700, annulé à 500 quand le fournisseur de fenêtres prend trois secondes, même si le scan a commencé juste après le relâchement. Deux scénarios échouent, six assertions : première observation et poll déjà en attente.
- Contrôle santé : le client CLI sans permission AX signale un échec qui ne décrit pas le daemon. La requête socket query health répond en 734 ms avec les quatre contrôles OK. Il s'agit d'un diagnostic trompeur, pas d'une permission manquante du daemon.


## Contre-vérification de la veille

15 756 événements du 16 octobre (00:00–23:49 CEST) conservés et contrôlés :
28 échecs, 6 restaurations externes et 3 redimensionnements reconnus. Les derniers
refus Firefox sont suivis de l'acceptation du cadre observé après épuisement du budget,
sans boucle non bornée (22:26:52–22:26:57). Aucun mécanisme distinct démontré.
L'archive complète remonte au 13 octobre ; aucun journal original supprimé.
