# Recherche et décisions

## Mode réservé

Décision : commande `roadie toggle maximize`. Raisons : distinction courte avec fullscreen et native-fullscreen ; bascule explicite même si une fenêtre seule remplit déjà la zone disponible. Alternatives : ajouter une option fullscreen ou changer fullscreen ; rejetées pour conserver les commandes actuelles.

## Géométrie

Décision : utiliser le visibleFrame et les outerGaps de fenêtre seule, puis forcer left >= RailSettings.width. La largeur est réservée seulement quand le rail est visible. En repli auto-hide non pin, utiliser exactement visibleFrame ; pin force la réservation avant la prochaine mesure, puis les révélations/replis suivent visibleWidths par écran. RailPanel.position/configureAutoHide applique exactement config.railWidth ; RailVisualConfig.load lit settings.width. Le contenu de StageCardView (224) n'est pas une autre surface de fenêtre. Aucun changement de dimension du panneau dans cette feature.

## Restauration et compatibilité

Décision : champs Codable optionnels zoomReservesRail et restorePlacements. Un ancien intent sans réservation reste un plein écran Roadie. Les transitions entre modes gardent une seule sauvegarde. Les modes arbre réutilisent leur arbre ; les modes sans arbre retrouvent les placements sauvegardés valides, avec repli au plan normal si les fenêtres/écrans ont changé. Float restaure seulement les fenêtres toujours présentes.

## Maintien

Décision : recalculer la cible réservée dans les plans et le maintien. Réutiliser fullscreenEntries pour protéger la stage ; adapter les chemins de recalage, focus et retour de stage qui supposent actuellement une taille plein écran. Refus : vérifier le cadre accepté avant de cacher les voisines.

## Tests

Baseline consultée : ~/.speckit/research/08-testing-quality.md. Tests orientés comportement de bout en bout commande/provider/writer/stores, plus persistance et CLI. Sources consultées : [The Practical Test Pyramid](https://www.martinfowler.com/articles/practical-test-pyramid.html) et [Test Behaviors, Not Methods](https://testing.googleblog.com/2014/04/testing-on-toilet-test-behaviors-not.html). Elles justifient des assertions sur les cadres/restaurations observables et les chemins d'intégration, sans figer l'organisation des méthodes.

## Contre-revue indépendante

Détection : bridget who ne montre aucun agent connecté. Le catalogue T3 n'expose aucune orchestration ; tentative directe orchestrator_capabilities : fonction absente. T3_ACP_MCP_NODE non défini. Aucun agent d'un autre fournisseur joignable. Étape inter-fournisseurs sautée ; audit séparé du code prévu.

## Charge future

Pas de nouvelle dépendance, pas de nouveau store. Deux propriétés optionnelles explicables et un calcul métier partagé. Les comportements existants restent couverts par leurs tests.
