# Spécification 079 - Phrase complète et actions gardées

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`), idées H et K validées : « fire perso
gauche » en une ligne, dans la langue de l'application, français et anglais à défaut d'un système
de traduction ; ⌘S garde une action en abréviation ou en commande (« c'est énorme cette fonction »).

## Demande reformulée
Taper une phrase dans Capslock + F : un objet, puis une destination et une position, en français
ou en anglais (`fire perso gauche`, `fire perso left`). La barre affiche sa compréhension avant
Retour. ⌘S sur une action composée la garde : une abréviation de 12 caractères au plus, qui la
refait depuis la barre, et la commande `roadie launch` équivalente, à copier pour
BetterTouchTool.

## Dépendances
SPEC-073 à 078 ; lot 3 F10 (alias) avancé ici.

## Exigences
- **FR-001 Phrase.** Saisie de plusieurs mots dont les derniers sont reconnus : nom d'une stage
  (exact, ou début unique d'au moins 3 lettres), `ici`/`here`, `nouvelle`/`new`, `bureau N`/
  `desktop N`, `écran N`/`screen N`, et une position `gauche`/`left`, `droite`/`right`,
  `plein`/`full`, `flotte`/`float`. Les premiers mots cherchent l'objet. Une ligne « Phrase » en
  tête annonce l'action (« Ouvrir Firefox dans Perso, à gauche ») et Retour la fait.
- **FR-002 Verbe.** Application, fichier : ouvrir dans la stage (ou ici, nouvelle stage) ; fenêtre :
  envoyer vers la stage, le bureau, l'écran, ou amener ici ; stage : déplacer vers un bureau ou un
  écran. Position seule : ouvrir ou aller à la fenêtre, puis la position.
- **FR-003 Position.** Après le placement, la fenêtre va à gauche ou à droite (déplacement dans la
  disposition), plein écran (maximiser) ou flotte.
- **FR-004 ⌘S.** Sur une application, un fichier, une phrase ou un verbe composé d'une
  application ou d'un fichier : étape « Garder » ; la saisie est l'abréviation ; Retour l'enregistre ;
  ⌘C copie la commande `roadie launch` équivalente. Fenêtres, stages, cibles : refusé avec la
  raison (ils ne survivent pas à leur fermeture).
- **FR-005 Abréviation.** Taper exactement une abréviation met sa ligne en tête ; Retour refait
  l'action ; la stage est retrouvée par son nom au moment de l'usage. Fichier
  `~/.roadies/launcher-aliases.json`, local.
- **FR-006 Commande.** `roadie launch CHEMIN [--stage NOM | --here | --new-stage] [--position
  left|right|full|float]`.

## Critères de réussite
- Tests : `fire perso gauche` et `fire perso left` donnent la même action ; `fire` seul ne donne
  pas de phrase ; un mot inconnu à la fin ne donne pas de phrase.
- ⌘S puis `fp` puis Retour : `fp` donne la ligne de l'action en tête.
- La commande copiée relancée en terminal fait la même action.

## Hors périmètre
Traduction de l'interface ; phrases à plusieurs objets ; abréviations de fenêtres ou de stages.
