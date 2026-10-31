# Analyze145 et convergence

Fallback manuel : primitives slash/converge non exposées ; protocole des compétences appliqué. Spec, plan, tâches, sources du propriétaire, moniteurs, focus, LiveDropPreview, dispatcher, masquage et tests lus. Pas de conflit CRITICAL non résolu.

|Exigence|Réalisation et preuve|Conclusion|
|---|---|---|
|FR1 vraie source entre écrans|WindowDragNativeRelease.finish et capture dans DropPreviewController ; garde d’écran retirée dans LiveDropPreview.showsRealSource ; test Spec144RealDropTests.anotherDisplayKeepsRealSourceAndRestoresItOnCancel ; huit parcours natifs dont capture région|Vérifiée sur deux écrans/AppKit/Chrome observés|
|FR2 annulation/dépôt|LiveDropPreview.finish, InteractiveFrameDispatcher et StageCommandService.place existants ; annulation3cadres et dépôt sans saut dans les deux sens|Vérifiée|
|FR3 geste et contrôles|Séquence de pointeur, marqueur, bouton logique et hook du vrai relâchement ; tests145 du marqueur/moniteur/blocage ; onglets et titre Chrome observés|Vérifiée avec limite : toutes les applications/contrôles ne sont pas certifiés ; bouton fermer la fenêtre non rejoué|
|FR4 autorité et réutilisation|Identités CG ID/PID et AX existantes ; aucun API privé nouveau, TCC, Dock ni dépendance ; permis/générations/refus conservés|Vérifiée à la lecture et aux essais|
|T007 masque déjà atteint|FrameTransitionRuntime réutilise HiddenWindowPlacement et cache mémoire ; red/green parking ; restauration précise et stable après redémarrage|Vérifiée|

Analyse après correction : les états nouveaux servent une règle du geste (fin native distincte de la fin utilisateur). Les files géométriques et la persistance restent uniques. Tap : O(1) par mouvement, O(w) au clic sur mémoire publiée, aucune AX/disque. Qualification AX détachée unique et remplacée. Bail existant renouvelé au plus2Hz depuis le minuteur existant. Masquage : O(k×d), d=écrans ; préexistant O(k) calcul animé ; aucun relevé AX ajouté. Pas de nouveau framework ni service.

Converge : CONVERGED, un passage après T007 ; aucune tâche ajoutée par cette confrontation. La tâcheT007 avait été ajoutée pendant l’implémentation après une observation réelle. Limites maintenues dans validation.md ; aucune exigence réduite pour masquer un échec. Phase livraison à terminer séparément.
