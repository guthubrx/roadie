# Recherche et décisions 061

- Référence produit approuvée : /tmp/roadie-archipel-baies-loupe.html. Le survol remplace le clic de consultation de cette maquette.
- AppKit NSTrackingArea documente mouseMoved et la zone visible : https://developer.apple.com/documentation/appkit/nstrackingarea . Utiliser des événements réels et une stabilisation évite qu’une nouvelle géométrie entraîne seule une autre cible.
- BTT Trigger JSON Definitions : https://docs.folivora.ai/docs/json/trigger-definitions/ . Le geste discret trois doigts vers le haut porte le type 102. Confirmer le schéma de l’installation et les déclencheurs existants avant écriture, par API AppleScript officielle.
- WindowSwitcherService.load acquiert un readerSnapshot et enrichit hors main ; activate réutilise focusWindow avec propriété vérifiée. Étendre le résultat nommé par snapshot pour éviter une seconde acquisition.
- DesktopsConfig.count vaut 10 : ne pas fabriquer dix bureaux sur chaque écran. Retenir bureaux actifs, occupés et nommés, plus stages nommées vides.
- RailThumbnailStore.shared contient une rétention par propriétaire et un seul lot de capture. Ajouter owner overview ; pas de capture déclenchée par survol.
- TargetSearchHotkey possède une signature Carbon fixe ; la rendre injectable avec ses valeurs actuelles par défaut. Le registre du sélecteur ne doit pas être instancié deux fois.
- Magnification : pourcentage de taille de l’aperçu de fenêtre, borné par la zone visible. Un seul bureau ne grossit pas au-delà de la région. La vue ne prétend pas contenir des fenêtres infinies lisibles sur une page.
- Les baselines tests et constitution projet sont réutilisées ; aucune performance chiffrée revendiquée sans mesure. Les cas minimaux sont 11, 32 et 64 fenêtres et deux dispositions.
