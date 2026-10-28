# Session 110 : un calcul peut aussi ouvrir Calculette

## Besoin

Dans la barre, Retour sur un calcul copie le résultat et ferme la barre (session 087). L'utilisateur
veut garder cette copie, et pouvoir aussi ouvrir Calculette, selon un réglage.

## Règle

- Réglage `calc_opens_calculator` dans `[experimental.target_mode]`, désactivé par défaut. Paramètres >
  Recherche : « Calcul : ouvrir aussi Calculette ».
- Retour sur un calcul copie toujours le résultat.
- Réglage actif : Retour ouvre aussi Calculette, par le même chemin que Retour sur l'application. Si
  Calculette est déjà ouverte, Roadie va à sa fenêtre, dans sa stage et son bureau.
- Le sous-titre annonce l'effet : « Retour copie » ou « Retour copie et ouvre Calculette ».
- ⌘C copie sans ouvrir, réglage actif ou non.
- Calculette absente du catalogue des applications : Retour copie seulement, comme avant.

## Hors périmètre

- Taper le résultat dans Calculette (touches simulées vers une autre application). ⌘V suffit.
- Choisir une autre application de calcul.
