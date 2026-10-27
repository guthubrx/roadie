# Spécification 096 - Barre vide : Souvent ici et Recherches récentes réglables

Demande du 27 octobre 2026 : « il faut que "souvent ici" et "recherches recentes" soit paramétrable en
activation et en profondeur dans le menu paramètre si ce n'est pas encore le cas ».

## Constat
- La barre vide (SPEC-081) montrait toujours 3 lignes « Souvent ici » et 3 lignes « Recherches
  récentes » (`prefix(3)`, `recent(3)`), sans réglage.

## Exigences
- **FR-001** `idle_frequent_enabled` (défaut vrai) affiche ou retire « Souvent ici » ;
  `idle_frequent_count` (1 à 10, défaut 3) fixe son nombre de lignes.
- **FR-002** `idle_recent_searches_enabled` (défaut vrai) affiche ou retire « Recherches récentes » ;
  `idle_recent_searches_count` (1 à 20, défaut 3 ; l'historique garde 20 saisies) fixe son nombre de lignes.
- **FR-003** Les quatre réglages figurent dans Paramètres > Recherche, table `experimental.target_mode`.
  Une valeur hors plage est ramenée à la borne. Les défauts gardent le comportement actuel.

## Critères de réussite
- SC-001 Tests : défauts, lecture du fichier, bornes, présence dans le catalogue des Paramètres.

## Hors périmètre
Autres rubriques de la barre vide (Règle proposée, Revenir, Annuler, Fermées récemment).
