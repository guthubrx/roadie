# Modèle de données — session 024

Aucun format persistant ne change.

- Affectations initiales : liste ordonnée `(WindowID, StageScope)`, groupée par scope.
  Un Set des identifiants, parcourus à l'envers, garde la dernière occurrence.
- Scopes modifiés : Set de StageScope admissibles avant validation géométrique.
- Rapprochement : groupes par signature application/titre déjà existante.
  L'index privé contient un arbre équilibré, boîtes 4D, comptes actifs et parents.
  Chaque arbre est créé à la demande et détruit à la fin de la réconciliation.
- Score : distance L1 des centres et demi-dimensions. Seuils métier inchangés.
- Retrait : identifiant candidat réclamé globalement, occurrences désactivées dans l'index.

La construction des appartenances exige un état neuf sans fenêtre affectée.
Une référence à un scope inconnu est refusée avant toute mutation. Modes, noms
et groupes sont conservés ; le focus réel est restauré ensuite par le snapshot.
