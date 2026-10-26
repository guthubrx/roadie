# Spécification 090 - Le web dans le lanceur : repli, adresse tapée, mots-clés, historique

Demande du 26 octobre 2026 (`/my.specify-all 086 a 091`), ligne 090 du tableau validé : « ligne
de repli, adresse tapée, mots-clés, historique ». Priorité 1 restante de la référence Alfred
(repli et adresse tapée) et deux priorités 2 (recherches par mot-clé, historique des requêtes).

## Demande reformulée
Quand rien d'utile ne correspond, la barre propose de chercher le texte sur le web. Une adresse
tapée s'ouvre telle quelle, dans le navigateur, ou dans la stage choisie par Tab. `yt chat`
cherche « chat » sur YouTube ; la liste des recherches se règle dans le TOML. La barre se
souvient des dernières saisies : rouverte dans les 5 minutes, elle reprend la dernière, et la
barre vide propose les recherches récentes.

## Dépendances
SPEC-075 (⌃ Retour et `web_search_url`), SPEC-081 (barre vide), SPEC-089 (recherches de repli
des workflows, ajoutées à ces lignes).

## Exigences
- **FR-001 Ligne de repli.** Toute saisie non vide (hors mode chemin et mode commande) se termine
  par une section « Web » : « Rechercher « … » sur <moteur> » pour `web_search_url`, puis les
  recherches de `fallback_searches` (mots-clés de la liste FR-003, défaut vide). Elle n'est
  choisie par défaut que s'il n'y a aucune autre ligne.
- **FR-002 Adresse tapée.** Une saisie sans espace qui est une adresse (`https://…`, `http://…`,
  ou nom de domaine avec un suffixe connu, éventuellement suivi d'un chemin : `github.com/x`,
  `localhost:3000`) donne en tête une ligne « Ouvrir <adresse> », choisie par défaut. Retour
  l'ouvre dans le navigateur par défaut ; Tab propose Ouvrir, Ouvrir dans… (une nouvelle fenêtre
  du navigateur rejoint la stage choisie), Amener ici, Copier.
- **FR-003 Recherches par mot-clé.** Table `[[experimental.target_mode.web_searches]]` (`keyword`,
  `title`, `url` avec `{query}`). Défauts quand la table est absente : `g` Google, `yt` YouTube,
  `wp` Wikipédia (fr), `ddg` DuckDuckGo, `maps` Plans. `yt chat` donne en tête « Rechercher
  « chat » sur YouTube », choisie par défaut ; `yt` seul propose de taper la recherche.
- **FR-004 Historique.** Les 20 dernières saisies qui ont mené à une action sont gardées dans
  `~/.roadies/launcher-history.json`. Barre rouverte moins de 5 minutes après : la dernière saisie
  revient, entièrement sélectionnée (la frappe la remplace). Barre vide : section « Recherches
  récentes » (3 lignes), Retour remet la saisie.
- **FR-005 Confidentialité.** L'historique ne quitte pas le Mac ; `roadie launcher history
  --clear` l'efface. Le journal ne contient ni saisie ni adresse complète (seulement l'hôte).

## Critères de réussite
- `github.com/guthubrx` → ligne « Ouvrir https://github.com/guthubrx » en tête ; `fichier.txt`
  (suffixe de fichier) ne devient pas une adresse ; `a.b` non plus sans suffixe connu.
- `yt chat` → YouTube en tête ; `zzqx` sans résultat → ligne web choisie par défaut.
- Barre rouverte après 2 minutes : la saisie précédente revient sélectionnée ; après 6 minutes : vide.

## Hors périmètre
Historique des adresses visitées, signets, suggestions de recherche en ligne.
