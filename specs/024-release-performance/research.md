# Recherche locale — session 024

L'audit complet 03 et ses contre-audits confirment les trois parcours, au commit
`4643ae4d`. Ils n'ont mesuré ni CPU ni latence ; leurs coûts proviennent du code.
La branche intégrée contient encore les trois chemins.

- PERF-010 : `removeWindow` parcourt les stages pour chaque affectation du snapshot.
- PERF-011 : `authoritativeModelScopes` valide l'intent dans un compactMap par fenêtre.
- PERF-012 : `bestReplacement` filtre, calcule et trie un groupe homonyme à chaque membre.

La recherche des deux minima en une passe supprime le tri mais conserve le coût
répété sur les homonymes ambigus. Un index géométrique éphémère permet de partager
le travail et de couper les branches dont la distance minimale ne peut améliorer
les deux meilleurs résultats. Il faut retirer les candidats réclamés et garder
les gardes métier. Aucun nombre arbitraire de candidats ni abandon par délai.

Les données sont locales ; aucune recherche externe ni nouvelle bibliothèque nécessaire.
Les conclusions seront complétées par les mesures et la revue autorisée.
