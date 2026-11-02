# Plan151

## Intégration
- Deux valeurs de TilingConfig, sérialisation/validation et choix FR/EN dans les paramètres : drag_move_modifier=control, drag_resize_modifier=control+option. Chaîne vide désactive l’action.
- Petit contrôleur de capture CGEventTap uniquement dans le processus tiler/run. Réutiliser KeyEventTapOwners pour la durée de vie du contexte C. La cible vient du cachedGestureSnapshot, respecte l’ordre des surfaces visibles et est choisie au clic. Réserver la séquence down/drag/up ; sous le seuil de déplacement, rejouer la paire marquée pour conserver le clic. Les événements rejoués sont ignorés par le capteur.
- Un runtime de geste partage InteractiveFrameDispatcher/InteractiveWritePermit. Une opération active et le dernier lot par PID. Toutes les cibles (source et voisines) passent dans cette même file ; aucune écriture AX sur MainActor. Préparer une fois le contexte, les originaux et les minima. Géométrie provisoire sur MainActor ; validation d’état à cadence bornée et finale.
- Mouvement : réutiliser DropPreviewEngine et StageCommandService.place, pas un second algorithme de dépôt. Une seule file applique le mouvement source et les placements provisoires ; restauration des fenêtres touchées sur Échap. En flottant, garder le cadre choisi au relâchement.
- Resize : réutiliser BSPNativeResize et ses minima pour les stages à arbre persistant. Exposer ses bords mobiles pour choisir un coin valide depuis n’importe quel point. Le même dispatcher écrit source et voisines. Persister une fois via mutateChecked. Les autres modes suivent le chemin existant de fin de geste du maintainer.
- UserInputActivity tient le verrou de capture jusqu’à la fin du lot et de la validation. Le tiler ordinaire reste suspendu ; on ne lance ni NativeResizeRuntime observateur ni LiveDropPreview écrivain en parallèle pour ce geste explicite.

## Contrôles
Tests de choix/priorité des modificateurs, seuil, clic non glissé, annulation et désactivation ; géométrie/minimums/cadres restaurés ; génération périmée, fermeture et file occupée. Suite Swift séquentielle puis construction signée. Revue indépendante du plan et du code, essais sur application fictive, preuves avec limites explicites, installation/push et nettoyage.
Outil Sequential Thinking non exposé dans le catalogue de cette session : les choix et alternatives sont consignés ici avant le code. Une capture supplémentaire dans chaque composant et un writer parallèle à l’aperçu existant sont écartés pour éviter doubles prises de souris et conflits de générations.


## Ajustements après revue du plan
- Le tap de titre existant ignore les combinaisons destinées aux gestes explicites, indépendamment de leur ordre d’installation. La capture nouvelle ne dépend pas du style d’aperçu. Les paires rejouées portent un marqueur commun ; UserInputActivity et les moniteurs du rail les ignorent pour les gestes, tout en gardant la trace d’entrée utilisateur.
- Le callback de début de geste natif dans main refuse une souris déjà revendiquée. Le nouveau runtime ne lance pas NativeResizeRuntime ni LiveDropPreview : il utilise directement la géométrie pure et la file partagée.
- StageCommandService.place reçoit un chemin optionnel deferGeometryUsing et une validation transactionnelle. Avec ce chemin, le snapshot est fourni et seuls l’affectation, l’ordre, l’arbre et l’intention sont enregistrés ; aucune acquisition ou écriture AX au relâchement. Le comportement existant reste identique si cette option est absente. La passe normale reprend ensuite les écarts résiduels.
- Flottant : déplacement/redimensionnement libres avec sauvegarde de lastFrame pour un pin ; pour les règles hors stage, FloatingPlacement existant reprend son observation à la passe suivante.
- Combinaisons exactes, Capslock ignoré. Ctrl+Alt redimensionne ; si les choix sont identiques, le resize est prioritaire, comme annoncé dans l’aide. Seuil8points partagé avec les gestes existants.
- La géométrie et les lectures d’état sont préparées hors du callback. Le point est simplement remplacé pendant le mouvement, puis traité au plus à60Hz. Les lectures JSON de validation sont limitées à4Hz, avec contrôle final imposé. Les lectures de type CG nécessaires à une mesure native ne sont pas remplacées par des hypothèses.
