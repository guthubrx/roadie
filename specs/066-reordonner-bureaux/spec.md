# Spécification 066 - Réordonner les bureaux dans la vue d'ensemble

Demande du 25 octobre 2026, validée avec deux choix : renuméroter comme Mission Control
et ajouter une commande en ligne.

## Comportement
- Glisser la puce d'un bureau vers l'espace visé du même écran : au-dessus du premier,
  entre deux bureaux ou après le dernier (choix de l'utilisateur après un premier essai
  où la cible était le bureau entier, jugé peu intuitif).
- Le bureau déplacé prend le numéro de sa nouvelle place ; ceux d'entre les deux glissent
  d'un cran. Stages, fenêtres, nom, épinglages, signets, historique, protection de focus,
  origine des stages garées et intentions de disposition suivent le bureau.
- Aucune fenêtre ne bouge. Les raccourcis et les règles `assign_desktop` visent un numéro.
- Trait d'insertion fin, translucide, en dégradé, sans point central.
- CLI : `roadie desktop move N POSITION`.
