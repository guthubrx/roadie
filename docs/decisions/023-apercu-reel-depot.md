# ADR 023 — Aperçu réel et réversible du dépôt

Date : 2026-10-31. Statut : accepté.

## Contexte
Le fantôme de dépôt calcule déjà la future place de toutes les fenêtres. L’utilisateur demande que les voisines montrent réellement ces places avant le relâchement, avec une option pour conserver le fantôme seul.

## Décision
DropPreviewController conserve le contexte de visée initial. LiveDropPreview applique uniquement les cadres provisoires des voisines via le dispatcher interactif de la session 142. Aucun arbre, ordre ou affectation n’est sauvegardé. La dernière cible remplace les précédentes par PID. Les fenêtres sorties du candidat reviennent à leur cadre initial. Un contrôle temporaire vérifie le contexte et les changements du réglage.

Au dépôt, vider les lots pendant 500 ms au plus puis révoquer le permis avant la commande existante. Conserver les cadres d’aperçu pendant cette transition pour éviter un aller-retour visible. À l’annulation, le même dispatcher restaure les cadres initiaux. Une nouvelle génération, une portée modifiée ou un nouveau geste invalide la session ancienne. Ne pas restaurer par-dessus une commande nouvelle.

## Conséquences
Un seul moteur de dépôt et un seul writer AX. La fenêtre tenue reste au système. Coût ajouté linéaire en nombre de fenêtres et de stages par changement de cible ; pas de minuteur au repos. La visée sur les cadres initiaux évite l’oscillation causée par l’aperçu.

Une écriture AX déjà engagée n’est pas annulable (ADR 022). La permission est vérifiée entre attributs et avant publication ; la clôture bornée empêche une application lente de bloquer indéfiniment. Les miniatures de la vue d’ensemble gardent leur comportement propre.
