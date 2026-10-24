# Plan 061 - Vue d’ensemble

## Architecture et choix
Swift 6 / AppKit, macOS 14, aucune dépendance ajoutée. Réutiliser WindowSwitcherService pour inventaire et activation, RailThumbnailStore.shared pour images, SettingsService pour persistance, TargetSearchHotkey avec signature dédiée pour le raccourci facultatif et DistributedNotificationCenter pour les commandes CLI.

Créer une configuration OverviewConfig distincte, une projection hiérarchique pure OverviewModel et sa géométrie, un panneau AppKit et un contrôleur de session. Cette séparation correspond à un usage global persistant, différent du parcours MRU du sélecteur. Étendre load() avec le snapshot déjà acquis pour projeter les contextes sans seconde acquisition. Le panneau réutilise les cartes du sélecteur si leur rendu respecte le contenu entier des images.

Archipel : régions d’écrans en colonnes, bureaux empilés. Baies : régions d’écrans en lignes, bureaux côte à côte. Traits obliques entre régions, cartouches d’identité, stages en grilles. Les fenêtres gardent leur ratio. Minima et défilement en forte densité. Ordre stable par identité, sans tri après survol. Loupe de fenêtre 100–250 %, défaut 150 %, redistribution bornée aux voisins. Survol différé environ 100 ms seulement après mouseMoved réel, avec validation de session. Sélection clavier distincte de la loupe et du contexte actif.

Contrôleur MainActor : une acquisition annulable par ouverture, fermeture Échap/clic extérieur, captures bornées seulement pendant la session. L’activation réutilise la transaction focusWindow. Un échec reste visible dans le panneau. Réglages de disposition/loupe/% modifiables dans la vue et persistés via SettingsService ; aucune réaffectation du StageStore pendant consultation.

## Constitution et risques
Respect des identités, aucun AX supplémentaire au survol, pas de nouvelle file ni transport. Complexité géométrique O(écrans+bureaux+stages+fenêtres), recherche de cible O(bureaux) sur mouvement seulement. La lecture AX et la capture restent dans leurs chemins existants. Risques : relayout sous pointeur, densité, snapshots indisponibles, collision Carbon, conflit geste Mission Control. Tests purs puis parcours natif et lecture BTT. Sans outil Sequential Thinking exposé, les alternatives sont tranchées ici explicitement : réutiliser l’inventaire plutôt que scanner ; panneau séparé plutôt que modifier le cycle du sélecteur ; mouvement réel plutôt que mouseEntered pour éviter les oscillations.

## Validation et livraison
Tests config/persistance/CLI, hiérarchie homonyme et vide, géométrie 11/32/64, loupe bornée et parcours clavier/survol. Suite Swift séquentielle et scripts. Revue indépendante sans confirmation. Preuves natives dans preuves-corrections ; captures originales hors Git. Sauvegarde et readback BTT API officielle avant/après. Docs FR/EN, validation, convergence, audit V15, commit, intégration main, push vérifié, installation signée avec procédure existante, nettoyage des seuls candidats éligibles. Conserver le worktree actif lié au fil.

Complément vérifié : ComponentLockFile existant déclare le récepteur overview pendant start/stop. La CLI refuse un ancien démon sans ce composant. Les stages utilisent des colonnes adaptatives ; leurs minima dépendent du nombre de rangées. Aucun événement disque n’est écrit par le survol de la loupe.

Convergence : projection initiale indexée par identité (bureaux, stages, labels, appartenance) avant parcours ; ensembles pour déduplication. Aucun lookup linéaire répété sur le même ensemble dans les boucles de construction.

Essai intermédiaire abandonné : remplacer les cartes étirées par des rangées de stages pondérées par leur contenu et des grilles dont les colonnes maximisent la surface utile des images. Les hauteurs restent liées au contenu. Une loupe flottante de fenêtre réutilise l’image déjà en cache ; ses cibles restent les rectangles des cartes. Elle n’ajoute aucun relevé ni capture au mouvement. La carte conserve sa hiérarchie, ses diagonales et ses îlots. Aucun nouvel outil de capture ou de raccourci.

Port graphique : règles rows/columns/split/grid de la référence HTML transposées en fonctions pures Swift. split utilise des sommes préfixées et une recherche dichotomique, O(s log s), sans copie de sous-tableaux. Le document reste défilable lorsque les cibles deviendraient trop petites. L’interface utilise les proportions 1440×900 : bandeau77 et carte occupant toute la hauteur restante, sans pied, avec mise à l’échelle commune. Une fenêtre survolée devient une carte dominante dans sa stage ; aucune superposition. La même fixture32 est rendue dans NSPanel et comparée à la référence HTML. Les essais de cartes flottantes antérieurs sont abandonnés, pas livrés comme résultat final.

Choix final après précision utilisateur : overlay NSPanel sans bord, frame égale à NSScreen.frame, niveau statusBar, sans Space dédié. Un moniteur Échap local temporaire ferme la vue même depuis un contrôle. dismiss annule le suivi du menu, retire le panneau et l’écoute avant activation. Switcher existant au niveau statusBar+1 conservé.
