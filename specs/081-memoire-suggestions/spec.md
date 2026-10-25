# Spécification 081 - Rouvrir, annuler, liste utile et règles proposées

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`), idées F, I et J validées : rouvrir une
fenêtre fermée à sa place et annuler un déplacement ; une liste utile avant de taper ; des règles
proposées, signalées par un petit chip à droite de la barre plutôt que seulement dans les
Paramètres.

## Demande reformulée
À l'ouverture de Capslock + F, avant toute frappe, la barre propose ce qui sert maintenant :
revenir à la fenêtre précédente, annuler le dernier déplacement, rouvrir une fenêtre fermée
récemment dans sa stage, les applications souvent choisies dans cette stage, et une règle quand
une habitude se répète (« Slack finit toujours dans Com »). Un chip à droite de la barre signale
une règle à proposer même pendant une recherche ; ⌘R l'affiche.

## Dépendances
SPEC-029 (fermetures confirmées), SPEC-056 (historique du focus), SPEC-073 à 080, règles
générées (affinité d'application, SPEC-075).

## Exigences
- **FR-001 Déplacements notés.** Chaque déplacement d'une fenêtre vers une stage (barre, rail, vue
  d'ensemble, menu, CLI) est noté : application, stage d'origine et d'arrivée, heure. 200 au plus,
  `~/.roadies/launcher-moves.json`, local.
- **FR-002 Annuler.** Dans les 10 minutes, si la fenêtre est toujours dans sa stage d'arrivée et que
  la stage d'origine existe : ligne « Annuler : remettre <App> dans <stage> » ; Retour la remet.
  Même effet par `roadie undo`.
- **FR-003 Rouvrir.** Fenêtres fermées confirmées depuis moins de 12 h, 3 au plus, les plus
  récentes d'abord : « Rouvrir <App> · <titre> », détail « fermée il y a N min · <stage> » ;
  Retour ouvre une nouvelle fenêtre de l'application (ou la relance) dans cette stage.
- **FR-004 Liste vide.** Barre vide : proposition de règle, Revenir (fenêtre précédente), Annuler,
  Fermées récemment, Souvent ici (3 applications les plus choisies dans cette stage). Chaque
  ligne porte ⌘1 à ⌘9. Dès la première lettre, la recherche normale remplace la liste.
- **FR-005 Règle proposée.** 3 déplacements au moins d'une application vers une même stage en
  7 jours, 75 % de ses déplacements, sans règle existante ni refus : trois lignes « Créer la règle :
  <App> toujours dans <stage> », « Plus tard » (24 h), « Jamais ». Créer écrit l'affinité
  d'application (`roadies.generated.toml`, relue avant écriture).
- **FR-006 Chip.** Une règle à proposer : la capsule à droite de la barre affiche « 💡 1 » à côté
  du compteur ; ⌘R vide la saisie et montre la proposition.

## Critères de réussite
- Tests : trois déplacements de Slack vers Com → une proposition ; un refus « Jamais » la retire ;
  une règle existante l'empêche ; un déplacement de 11 minutes n'est plus annulable.
- Réel : un déplacement par `roadie launch`/barre puis la ligne Annuler le défait.

## Hors périmètre
Chip sur le rail ; habitudes par heure de la journée ; contenu des fenêtres rouvertes (document).
