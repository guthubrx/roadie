# Spécification 125 - Fenêtres d'appoint toujours flottantes, par leur titre

Demande du 29 octobre 2026. Point de départ : le rappel de Thunderbird (« 1 Reminder ») est tuilé. L'utilisateur
veut le faire flotter sans faire flotter tout Thunderbird. Il pense aussi aux petites fenêtres d'Excel et d'autres
applications. « Le titre de la fenêtre, c'est souvent ça aussi que les applications utilisent. » « Il faut que ça
soit paramétrable, ajoutable, enlevable par l'utilisateur sur ses propres applis. »

## Constat
`roadie window explain` sur le rappel : AXWindow / AXStandardWindow, tous les boutons, plein écran actif,
redimensionnable. Pour macOS, il est identique à la boîte de réception. Seul son titre le distingue. Aucune
heuristique de taille ou de boutons ne peut donc l'écarter.

## Exigences
- **FR-001 Liste.** `[[exclusions.floating_windows]]` avec `app` (nom ou identifiant, sans casse) et `title`.
  Dans le titre, `#` remplace un nombre (le mot suivant accepte un « s » final) et `*` n'importe quel texte.
  Comparaison sans casse, sur le titre entier.
- **FR-002 Priorité.** Chaque ligne devient une règle de flottement de priorité 9 100, au-dessus des règles
  par application du menu Fenêtre (9 000). Le rappel flotte même si Thunderbird est « toujours tuiler ».
- **FR-003 Paramètres.** Paramètres > Règles > « Fenêtres toujours flottantes » : ajouter, modifier, retirer.
- **FR-004 Menu Fenêtre.** « Toujours faire flotter les fenêtres « # Reminder » » ajoute la ligne (nombres
  remplacés par `#`) ; si la fenêtre est déjà couverte : « Ne plus faire flotter les fenêtres… » la retire.
  Les commentaires du fichier de configuration sont conservés.
- **FR-005 Diagnostic.** `roadie window explain [ID]` : attributs lus par macOS et raison de la décision.
- **FR-006 Premier cadre.** Les critères de taille (panneau court, petite fenêtre de réglages) jugent le cadre
  de la fenêtre à sa naissance, et non sa taille une fois tuilée.

## Hors périmètre
Aucune fenêtre d'Excel ou d'autre application préréglée : la liste est vide par défaut.
