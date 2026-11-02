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
