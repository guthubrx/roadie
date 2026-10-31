# Recherche et audit de réutilisation
- Décision : étendre DropPreviewController. Motif : point commun déjà utilisé par titre et rail, candidats complets et visée figée. Évite un second moteur de dépôt.
- Décision : réutiliser InteractiveFrameDispatcher/permit. Motif : indépendance des PID, coalescence, même writer et registre. Pas d’AX dans callback souris.
- Alternative rejetée : appliquer StageCommandService.place à chaque mouvement. Cela persisterait l’ordre et l’affectation, ferait varier la visée et compliquerait l’annulation.
- Alternative rejetée : nouvelle animation de captures. Elle ne déplacerait pas les vraies fenêtres demandées.
- Validation : régler live_drag_preview n’est pas une modification de géométrie ; suivre l’exception resizeHandles dans SettingsLiveApplyController.
- Charge future : une seule session transitoire ; réutilisation du moteur de candidats et du writer. Aucun fichier de configuration secondaire.
