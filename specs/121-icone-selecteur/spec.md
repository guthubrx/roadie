# Session 121 : icône de l'application dans le sélecteur

## Besoin

Dans le sélecteur de fenêtres (Cmd+Tab), reconnaître l'application d'une fenêtre d'un coup d'œil : son icône à
côté du titre. Affichée par défaut, désactivable, avec une taille automatique adaptée et une taille réglable.

## Règle

- `[switcher] app_icon` (oui par défaut) : icône à gauche du titre, en vignettes (toutes présentations) et en liste.
  Le style Icônes garde toujours son icône : c'est l'image de la carte.
- `[switcher] app_icon_size` (0 par défaut, 0 à 64) : 0 donne la taille automatique ; sinon 12 à 64 points.
- Taille automatique : hauteur des deux lignes de texte moins 4 points (38 en texte de 16), 22 au plus en
  présentation compacte (une ligne), 28 en liste, 56 en style Icônes ; jamais plus d'un cinquième de la carte.
- Taille choisie : respectée jusqu'à la moitié de la carte ; plus haute que le texte, elle agrandit la ligne du
  titre (et donc la carte), le texte restant centré.
- Réglages globaux, communs à tous les profils.

## Hors périmètre

- Réglage par profil, icône posée sur la vignette, icône du grand aperçu (inchangée).
