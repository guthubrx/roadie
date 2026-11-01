# Session 149 — Placement et barre réactifs

Demande : corriger tous les problèmes confirmés par les journaux du 1 novembre 2026.

## Résultat attendu
- Les résultats finaux des placements animés alimentent les mêmes protections et diagnostics que les placements directs. Une même fenêtre en échec ne provoque pas des tentatives indéfinies.
- Une application lente pendant le relevé des fenêtres ne bloque plus les saisies et animations de Roadie. L’arbre, les affectations et les écritures restent contrôlés sur le fil principal.
- La barre recherche utilise l’acquisition asynchrone commune, sans transformer une acquisition invalidée en liste vide. Annuler ou ouvrir une autre commande pendant l’attente empêche toute ouverture tardive.
- Les réglages, gestes, proportions, premiers placements directs et restauration de focus restent conservés.

- Une fermeture de barre ou de grille invalide sa capture système. Un événement tardif ne peut pas accéder à une session détruite, ni cibler la session suivante.
- Les relevés rejetés ont une fréquence bornée et un diagnostic. Une échéance rejetée reste en attente.

## Validation
Tests de régression avec attente simulée et événements concurrents ; suite Swift séquentielle ; parcours natifs et mesures avant/après, limites déclarées. Aucun contenu privé des logs dans Git.
