# Session 120 : boutons Remote et cache des Script Filters

## Besoin

- `trigger.remote` : 3 workflows du corpus de 102, dont Audio Switcher installé chez l'utilisateur, restaient
  « partiels » pour leurs boutons d'Alfred Remote (iPhone). Remote lui-même n'est pas repris.
- `cache` des Script Filters (Alfred 5) : 5 workflows du corpus le demandent.

## Règle

- Un bouton Remote est une entrée : `roadie workflow trigger ID TRIGGERID` l'appelle comme un déclencheur
  externe (aussi `Call External Trigger`). Sans argument donné : son texte fixe (`argumenttype` 3), sinon aucun.
  `roadie workflow list --hotkeys` liste aussi ces boutons, avec la commande à lier dans BetterTouchTool.
- Cache : `cache.seconds` (5 à 86 400 s) garde la réponse pour la même entrée et la même saisie ; pendant ce
  délai, le script n'est pas relancé. `loosereload` (réponse gardée montrée puis rechargée) n'est pas distingué.
  200 réponses au plus, en mémoire seulement.

## Mesure

- Corpus de 102 : avant la session, 89 complets et 98 avec une entrée complète (après 117 et 118).
