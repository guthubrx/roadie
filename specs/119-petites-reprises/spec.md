# Session 119 : petites reprises d'Alfred

## Besoin

Réglages et commandes d'Alfred restés « à faire » ou « en partie » dans la référence, à faible coût.

## Règle

- Mots-clés `open` et `find` (`open_keyword`, `find_keyword`, vides : désactivés) : seuls les fichiers sont
  montrés, comme la recherche rapide ; après `find`, Retour montre le fichier dans le Finder.
- `file_types` : types de macOS (UTI) cherchés en plus (Extras « Archives », « AppleScripts » et Avancé d'Alfred) ;
  un type couvre ses sous-types. `file_excluded_folders` : dossiers écartés (chemins absolus ou en `~`).
- Calcul : `calc_decimal` (`system`, `point`, `comma`) pour le résultat ; `calc_grouping` sépare les milliers,
  aussi dans ce qui est copié. La saisie accepte toujours point et virgule.
- `show_scrollbar` : curseur à droite de la liste, hauteur et place proportionnelles aux lignes visibles.
- Recherches web fournies : 17 (ajouts : Google Images, Google Maps, Traduction, Wikipedia anglais, Amazon, IMDb,
  eBay, Bing, LinkedIn, X, GitHub, Wolfram|Alpha). Une table `web_searches` du fichier remplace toujours la liste.
- Commandes système : « Recharger les applications » (« reload » d'Alfred : le catalogue est refait) et
  « Reconstruire l'index Spotlight » (`mdutil -E /`, mot de passe d'administrateur demandé par macOS, second
  Retour exigé).

## Hors périmètre (écartés ou couverts)

- ⌘O : Retour ouvre déjà un fichier avec son application par défaut.
- Modificateurs de Retour réglables, aperçu dans la moitié droite, éditeur de thème : non repris.
