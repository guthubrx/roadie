# Implémentation

## Correction

- `rail.stages.slot_height` dans le catalogue et `fx.rail.stages.slot_height` dans TOML.
  Valeur par défaut 0 : hauteur automatique. Valeur explicite : au moins 80 points.
  Le même réglage concerne les cartes vides et occupées en mode aperçu.
- Le dessin réserve une colonne commune pour cinq couches maximum. L'éventail horizontal
  reste dans la largeur disponible. Un groupe d'une fenêtre et un groupe de cinq
  fenêtres ont la même vignette avant. Le test du clic reprend les mêmes cadres.
- Les noms restent dans les limites verticales de la carte compacte.
- Le trait d'insertion et le dépôt partagent une seule cible dans RailPanel.
  Le rang reste calculé dans l'ordre persistant complet. Les groupes vides nommés
  sont conservés par la projection déjà installée de la session parallèle.
- Les reconstructions de cartes attendent la fin du glisser droit. Le moniteur global
  relève la position avant le report sur la file principale. Un événement
  `rail_stage_drop` enregistre le point et le rang au lâcher.
- Les estimations de hauteur des cibles clavier acceptent aussi la hauteur explicite.
- Le validateur TOML connaît la nouvelle clé. Les bornes du catalogue et du parseur concordent.

## Validation avant installation

- Branche isolée : 1 477 tests, 159 suites, aucun échec.
- Copie combinée : 1 544 tests, 166 suites, aucun échec.
- Quatre nouveaux tests, dont neuf combinaisons largeur/rotation : 1 à 5 fenêtres,
  largeur 90/150/320, rotation 0/35/75 degrés, clic sur chaque couche, hauteur vide/occupée,
  lecture/écriture du réglage, panneau AppKit réel et ordre après dépôt.
- Le panneau mesuré donne 133 points entre centres : hauteur 120 + écart 13.
- Les anciens tests de projection à coordonnées fixes ont été adaptés aux nouvelles
  positions dessinées, en conservant la vérification du clic sur la couche arrière
  et de l'inversion de projection du point de prise.
- Premier passage combiné : nouveau réglage absent du validateur et compteurs du
  catalogue dépassés. Corrigés. Le balayage exhaustif des pixels des nouveaux tests
  occupait trop longtemps le fil AppKit et perturbait deux tests IPC. Le balayage
  reste réalisé sur cinq couches pour chaque géométrie, avec un pas de deux pixels.
  Le passage complet suivant réussit sans modification des tests IPC.

## Revue du changement

Revue locale du diff : calcul borné à cinq couches ; aucun scan AX pendant le mouvement ;
aucun nouveau moteur ni dépendance ; nettoyage du trait au lâcher, à l'annulation et
lors d'un geste interrompu ; rafraîchissement normal repris après le geste. Les raccourcis,
les noms, les identifiants et les groupes persistés ne sont pas modifiés.

Les vérifications du dépôt utilisent AppKit et le store. Elles ne simulent pas une
manipulation physique de la souris. Le journal au lâcher permettra de relier un prochain
signalement au point réellement reçu.
