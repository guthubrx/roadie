# Validation 149 — en cours

- Diagnostic initial : 38 tentatives finales échouées, parfois répétées sur la même fenêtre. Les résultats différés n’alimentaient ni la mémoire des échecs ni les événements par fenêtre. Échantillonnage natif du PID73795 : relevé AX du producteur sur le fil principal.
- Tests ciblés : 65 tests dans 10 suites réussis. Suite complète : 2443 tests dans 369 suites réussis en 117,777 s. Scripts : 28 tests réussis en 17,176 s. Aucune erreur de compilation résiduelle ; avertissements historiques conservés.
- Parcours comparatif avant : huit ouvertures par `roadie workflow alfred search roadie149verificationaucunresultat`, fermeture par grille interactive de 0,1 s. Les huit sessions et panneaux sont observés. first_draw entre 192 et 502 ms ; max_stall entre 59 et 185 ms. Cette série ne reproduit pas la pause historique de 2,102 s.
- Les captures de ce parcours montrent seulement la saisie fictive. Les traces brutes restent hors Git.
- Limite des gestes : CUA ne fournit aucune surface (CUA_REPL_ENABLED_SURFACES is required). Le pilote temporaire ne dispose pas de l’autorisation PostEvent/Accessibility ; aucune permission modifiée. Les parcours natifs emploient les commandes existantes, pas des frappes système simulées.
- Installation, comparaison après, revue et clôture Git : en cours. Aucun verdict favorable indépendant annoncé.

## Essai de réponse lente sur une application fictive
Une petite application de validation crée une fenêtre standard, sans document. Sur ordre du pilote local, elle décale son cadre de 2 points puis bloque son propre fil principal pendant 1,2 s. Aucun processus utilisateur n’est suspendu. La barre est déjà ouverte sur une recherche fictive avant ce changement. Trois essais espacés de 6 s laissent expirer la mise de côté AX.
Avant : max_stall = 579, 517, 544 ms. Le problème de réactivité est ainsi reproduit indépendamment des documents et des applications de l’utilisateur. L’attente maximale de chaque appel AX reste fixée à 0,5 s.
Dernière suite complète avant les derniers ajustements de fermeture : 2446 tests /369 suites réussis en72,026s. La suite finale et la compilation de livraison sont relancées après simplification du contrôle de tâche et du nettoyage de la barre.

## Vérification de la source finale
56 tests ciblés de cycle de vie dans8suites réussis, puis2446tests/369suites séquentiels réussis en71,871s. Les28tests de scripts étaient déjà verts et leur source est inchangée. Le contrôle souris du test d’arrêt est injecté pour ne pas dépendre du geste réel de l’utilisateur. Les empreintes Sources/Tests sont enregistrées hors Git avant la compilation finale.

## Deuxième cause mesurée
La première activation (UUID9535DD0D-DF3D-3C97-A477-2142F33E2947, PID10092, santé5/5) déplace correctement le relevé du producteur, mais les trois essais de réponse lente donnent encore139,473,590ms de max_stall. Cette validation ne suffit donc pas à déclarer le problème résolu.
L’échantillonnage natif attrape504échantillons du fil principal dans AXWindowEventObserver.handleEvent → windowID → _AXUIElementGetWindow. Le callback relit aussi le cadre AX sur le fil principal. Correction ajoutée : identité locale des fenêtres déjà surveillées ; une lecture de cadre active et la dernière demande en attente par fenêtre, hors MainActor. Annulation à la destruction/fin et rejet des observations d’une ancienne génération.
62tests ciblés dans13suites réussis, puis2449tests/370suites séquentiels réussis en72,175s. Trois nouveaux tests couvrent attente/coalescence, arrêt pendant une lecture et impossibilité de confirmer un refus plus récent avec une ancienne lecture.

## Série prolongée et sauvegarde périodique
Après correction des callbacks : une série de trois essais donne64,70,73ms, puis une série prolongée de huit donne120,125,66,71,108,79,67,85ms. Le pic précédent de429ms reste mentionné ; aucune cause certaine ne lui est attribuée. L’échantillonnage70s confirme l’absence de longue lecture de cadre dans les callbacks. Il montre encore des relevés synchrones dans la sauvegarde de restauration et dans la commande grille, cette dernière exécutée après fermeture de la barre.
La sauvegarde périodique (30s) passe donc par readerSnapshot avec contrôle d’annulation et Mission Control avant/après lecture. Le démarrage et la sauvegarde finale de l’arrêt conservent leur contrat synchrone. Une seule tâche périodique ; arrêt annulé avant toute écriture finale. Tests :39ciblés/8suites verts, puis2451tests/370suites verts en72,046s. Les28tests de scripts restent verts.
Huit ouvertures ordinaires sur la validation activée : first_draw90–199ms, max_stall56–136ms ; avant first_draw192–502ms, max_stall59–185ms. Cette comparaison n’isole pas les variations de cache ou des autres applications et ne constitue pas une garantie universelle.
Preuve HTML relue dans html_preview : navigation, image réelle et lecture/pause vérifiés. Capture native de la saisie fictive ; couverture du clavier système toujours partielle. Activation de la sauvegarde périodique finale et revue indépendantes en cours.
