# Plan

Réutiliser UserInputActivity et l'acceptation de DividerResizeRuntime.begin. Retirer la suppression par coordonnées et l'état visibleHandles devenu inutile. Après acceptation seulement, la poignée reprend la propriété du geste et efface son interprétation native en attente. Un refus de poignée n'efface rien.

Une propriété interne partagée reconnaît les seules décorations borders sans titre ni AX ; réutilisation nécessaire pour garder le même critère entre occupation et ciblage. Le picker des gestes ignore ces décorations, sans modifier le picker du focus ordinaire. Coût O(w) au clic, pas de scan supplémentaire en mouseDragged.

Rejouer la situation avec quatre fenêtres : bord situé dans l'interstice, décorations au-dessus, nouvelle taille valide, puis vérification de l'arbre et de la stabilité. Tester aussi l'acceptation/refus explicite sans double geste. Compilation/test limité à deux tâches, installation avec signature/configuration conservées. Aucun benchmark supplémentaire ; priorité au geste perdu.
