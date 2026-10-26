# Validation 090

## Tests
- `Spec090WebTests` (4) : adresses (schéma, domaine, `www.`, port, `localhost`, IPv4, `readme.md/`)
  et non-adresses (`fichier.txt`, `a.b`, `readme.md`, `Safari.app`, `run.sh`, calcul, chemin) ;
  recherches par mot-clé et invite ; lignes de repli (`web_search_url` puis `fallback_searches`,
  mot-clé inconnu ignoré) ; nom du moteur ; repli choisi seulement dans une liste vide ; lecture de
  la table TOML ; verbes et variante ⌘ d'une adresse.
- `Spec090HistoryTests` (2) : 20 saisies distinctes, reprise sous 5 minutes, recherches récentes,
  magasin écrit puis effacé.
- Suite complète : 2 081 tests / 290 suites réussis.

## Installation
PID 32821 puis réinstallation après convergence ; santé 5/5 ; `roadie config validate` : seuls les
3 avertissements antérieurs. `roadie launcher history` : vide au départ.

## Limites
- Barre non essayée au clavier ; ouverture d'une adresse dans une stage non essayée (elle ouvrirait
  une fenêtre de navigateur chez l'utilisateur) : Chromium `--new-window`, Safari AppleScript,
  Firefox ⌘N puis l'adresse (onglet vide possible).
- « Copier le chemin » garde ce titre pour une adresse.
- La reprise sous 5 minutes masque les propositions de la barre vide (081) pendant ce délai.
- Contre-revue Bridget : refusée (`project_mapping_unknown`).
