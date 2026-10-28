# Session 113 : recherche dans le contenu et par étiquette

## Besoin

Reprise d'Alfred : mots-clés `in` (contenu des fichiers) et `tags` (étiquettes du Finder).

## Règle

- `in` + espace + mots : fichiers dont le texte contient chaque mot comme début de mot (Spotlight,
  `kMDItemTextContent == "mot*"cdw`), dans les familles déjà cherchées par nom.
- `tags` + espace + texte : fichiers et dossiers dont une étiquette commence par ce texte. Les couleurs
  du Finder sont enregistrées en anglais (`Red`) : rouge, orange, jaune, vert, bleu, violet et gris
  cherchent aussi leur nom anglais.
- Le mot-clé doit être suivi d'une espace (`inbox` reste une recherche par nom). Comme la recherche
  rapide, ces recherches ne montrent que des fichiers, dès 2 caractères.
- Réglages `content_search_keyword` (`in`) et `tag_search_keyword` (`tags`) ; vide : désactivé.
- Portée : comme Alfred, `~/Library/CloudStorage` (OneDrive, Dropbox, Google Drive) et
  `~/Library/Mobile Documents` (iCloud Drive) sont cherchés ; le reste de `~/Library` reste exclu.
  Cela vaut aussi pour la recherche par nom.

## Mesures (script jetable, ce poste)

- Contenu, texte partiel (`"*roadie*"cd`) : 3,0 s ; début de mot (`"roadie*"cdw`) : 0,1 s, même nombre
  de réponses. Décision : début de mot.
- Requête construite dans `NSMetadataQuery` : contenu + familles 0,17 s ; étiquette 0,11 s.
- Les 5 fichiers étiquetés « Red » trouvés étaient dans OneDrive (`~/Library/CloudStorage`) : d'où la portée.
