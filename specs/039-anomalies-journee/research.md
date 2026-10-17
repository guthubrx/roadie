# Données observées

Archives : /private/tmp/roadie-20261017-diagnostic. 10 834 événements du 17 octobre à 19:26:44 CEST. Daemon PID 96284, version installée 038, UUID historique 9B0A1CA9-9170-3AC4-B2C5-38ADC0E8EE97.

4364 live_tick journalisés : durée médiane 34,3 ms, p95 229,6 ms, max 5514,1 ms. Ces événements ne constituent pas tous les cycles du daemon. Le dernier relevé dure 3088,3 ms avec 11211,1 ms de retard. Rail : maximum journalisé 1900,4 ms, dont 1872,1 ms de snapshot.

Sample 3 secondes : 2474 échantillons main, 980 dans le relevé de fenêtres du tiler ; 325 dans le parcours des fenêtres attachées, dont 286 dans la résolution d'identifiants AX. Échantillonnage de temps mural, pas attribution CPU.

Le code date le cache partagé avant les lectures AX. Tout relevé dépassant 150 ms peut expirer avant sa publication (600 ms pour producteur). Le parcours attaché s'exécute même si tous les identifiants candidats sont déjà connus.

10 restaurations externes journalisées et 18 échecs de placement : analyse causale encore en cours. Aucun de ces compteurs ne prouve seul un bug.
