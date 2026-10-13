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


## Placements du 2026-10-13 — faits et invariants

Six signaux manual_resize_detected suivent une commande de stage.switch sur la fenêtre quittée. changedWindows considère tous les scopes connus et exclut seulement les arbres actifs ; nonTreeLayout peut donc supprimer l’intent d’une stage devenue inactive. Décision : observer seulement les changements pertinents du scope actif et ignorer le passage automatique caché/visible ; garder les vrais gestes.

La séquence d’activation montre une voisine cachée puis une sortie de zoom à la passe suivante. focusedHiddenRestore ne traite que les fenêtres déjà cachées. Décision : sortie logique avant le calcul du masque quand une autre fenêtre volontairement activée devient la cible. La course exacte entre les lectures de focus n’est pas observable dans ces traces ; les tests doivent borner ce cas.

Les 57 événements write_budget_exhausted concernent cinq couples requested/actual. Le budget partagé AX est par fenêtre et génération ; il n’est pas global. Aucun relèvement du budget décidé. Les logs actuels ne distinguent pas les erreurs d’attribut AX ou un état natif au premier refus. Toute modification de cette chaîne exige une preuve ou un diagnostic de refus précis.


Constat final : au point commun d’écriture, AXFullScreen n’était pas relu. Une lecture fraîche native empêche désormais les setValue ; cannotComplete interrompt le préflight avant consommation du budget et utilise la quarantaine existante. finishRun gardait cleanExitAt absent sur refus, ce qui faisait appeler le watcher « crash » malgré l’arrêt volontaire. La demande d’arrêt est désormais distincte du succès de restauration ; les échecs restent repris et portent leurs IDs. Aucune attribution précise du refus 1/6 à une application n’est démontrée par les anciens journaux.


Vérification du focus : snapshot.focusedWindowID peut être un repli mémorisé (provider AX=nil). Une activation de voisine visible exige désormais une cause de focus/activation/création et le même ID réel et validé. La lecture courante déjà utilisée pour le masque est partagée avant les deux chemins ; aucune lecture ajoutée. Le fallback de centrage ne sert qu’aux fenêtres réellement cachées. Le test de stage exige une disposition obtenue avant l’échéance, sans imposer une nouvelle écriture quand elle est déjà correcte.


Revue sur plusieurs passes : une voisine devenue cachée ne doit pas contourner la confirmation du focus réel. Le test à trois passes a montré une sortie au deuxième passage avec AX=nil, puis la garde a été étendue aux sorties de zoom de toute voisine. Les trois passages conservent désormais le zoom. CmdTab caché reste permis au polling sans événement explicite dès que le système confirme son ID. Aucun nouvel état ni lecture créé.
