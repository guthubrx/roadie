# Session 107 - La recherche des paramètres filtre la colonne de gauche

## Demande

« Je veux pouvoir chercher dans les paramètres sur tous les paramètres dans la colonne de gauche et ça filtre. »

## Exigences

- FR-001 Pendant une recherche, la colonne de gauche ne montre que les catégories qui ont des réglages trouvés,
  avec leur nombre, puis les réglages trouvés sous chaque catégorie (huit au plus, puis « et N autres »).
- FR-002 « Tous les résultats » montre tous les réglages trouvés à droite ; un clic sur une catégorie ne montre
  que les siens, sans quitter la recherche.
- FR-003 Un clic sur un réglage de la colonne fait descendre la zone droite jusqu'à lui et le surligne.
- FR-004 La recherche couvre aussi le nom de la catégorie et celui du groupe affiché (« Perspective », « Vue
  d'ensemble »), sans tenir compte de la casse ni des accents.
- FR-005 Échap dans le champ vide la recherche ; une nouvelle saisie revient à « Tous les résultats ».

## Hors périmètre

Les lignes des éditeurs de listes (règles, profils) ne sont pas cherchées une par une.
