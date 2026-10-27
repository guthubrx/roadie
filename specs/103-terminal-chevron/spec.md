# Session 103 - Terminal avec >

## Demande

« Je veux le terminal avec supérieur », comme le préfixe `>` d'Alfred.

## Exigences

- FR-001 : une saisie qui commence par `>` ne montre que la ligne du terminal : la commande tapée, ou une
  invite si rien n'est tapé après `>`.
- FR-002 : Retour lance la commande dans une nouvelle fenêtre du terminal de `terminal_app`, depuis le
  dossier personnel ; la fenêtre reste ouverte après la commande (le shell de connexion reprend).
- FR-003 : Terminal et iTerm par AppleScript (commande échappée) ; Ghostty, kitty, WezTerm et Alacritty
  par `open -na <App> --args`, sans chaîne interprétée par un shell intermédiaire ; Warp n'accepte pas
  de commande : il s'ouvre et la commande est copiée.
- FR-004 : terminal absent : la barre se ferme avec l'erreur `terminal_unavailable`, rien ne se lance.
- FR-005 : la commande lancée entre dans l'historique des saisies ; ⌘C copie la commande.
- FR-006 : réglage « Terminal de > » dans Paramètres > Recherche.

## Limites

Pas de variante ⌘↩ (nouvelle stage) : la fenêtre du terminal suit les règles de placement habituelles.
Ghostty 1.3 peut ouvrir un onglet dans une fenêtre existante plutôt qu'une fenêtre neuve.
