# Convergence 061

Protocole manuel exécuté sur le code final et les tests. Pas de primitive converge exposée. Tâches inchangées pendant cette lecture : Premier passage : T012 ajoutée pour les recherches répétées. Second passage final : CONVERGED après indexation et test de conservation de l’ordre. Les ajustements issus de l’observation native ont été faits avant ce passage et revalidés.

| Exigence | Réalisation | Preuve |
|---|---|---|
| FR01 | OverviewModel, WindowSwitcherService.load/activate | Identités, fenêtres présentes, activation native Chrome dans son contexte, tests056 conservés |
| FR02 | OverviewLayout.make, OverviewPanel | Deux dispositions et quatre combinaisons essayées dans l’application installée |
| FR03 | OverviewCanvas.mouseMoved, OverviewHoverState | Test natif du mouvement/délai/arrêt/reprise clavier ; pied de fenêtre réel Bureau4 puis Bureau1 ; contextes persistants identiques |
| FR04 | OverviewLayout.distribute, minima et document défilable | 11/32/64, 100/150/250 %, trois tailles, aucune carte perdue ou chevauchée |
| FR05 | OverviewController.show/hide/tick | UUID, annulation, timer supprimé, cache propriétaire distinct ; aucun accès dans mouseMoved |
| FR06 | CLICommandRouter overview, registre ComponentLockFile | Refus d’un démon ancien, test start/stop, show/toggle/hide/status natifs |
| FR07 | OverviewConfig, SettingsCatalogOverview, recorder | Config ancienne, bornes, persistance et raccourci vide ; capture de touches partagée058 |
| FR08 | OverviewPanel.sendEvent et contrôles natifs | Clics Baies/loupe/% reçus par AppKit et persistés ; Échap et Entrée par BTT ; geste physique trackpad non synthétisable |
| SC03 | Docs FR/EN, preuves, validation et tâches finales | Vérification Git/disque/runtime et audit à clôturer dans validation.md |

Aucune nouvelle exigence produit découverte après la lecture finale. Les limites de preuve du geste physique et de la revue distante ne sont pas masquées.

## Retour visuel et troisième passage
La version précédente a été refusée par l’utilisateur : les cadres et proportions divergeaient de la référence. T013 à T016 rouvertes/ajoutées. Le port final reprend les règles rows/columns/split/grid de la maquette avec test de coordonnées à 32 fenêtres et comparaison AppKit sur les mêmes images fictives. La loupe flottante est retirée. Le survol agrandit une carte dans sa stage, sans activation. Les îlots ne portent plus de grands cadres. L’interface entière reprend les proportions 1440×900 et le rendu sRGB de la référence.
Le geste physique trois doigts a été confirmé par l’utilisateur. Le doublon natif a ensuite été identifié : TrackpadThreeFingerVertSwipeGesture=2 dans deux domaines macOS. Sauvegarde puis valeurs0 relues, activateSettings -u exécuté ; pas de deuxième geste BTT102. L’essai physique après suppression du conflit reste distinct de la confirmation initiale.

Passage final après épuration T017 : CONVERGED sur Sources/Tests gelés avant la suite1918. Les tâches de réalisation T001–T008 et T012–T017 couvrent les exigences finales ; les tâches procédurales de gate/livraison restent distinctes. Le pied et les marqueurs turquoise des essais intermédiaires ne sont plus présents. Fermeture Échap et absence de Space vérifiées en test ; disparition native après touche vérifiée. Aucun nouveau manque fonctionnel trouvé ; limites de qualification conservées dans validation.md.
