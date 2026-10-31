# Plan146
Cause observée : première passe activation iTerm697,7ms sans commande ; passe safety suivante puis animation300,5ms. Pas de prise de contrôle avant première notification publique.

Réutiliser WrittenFrameRegistry pour reconnaître une fenêtre sans écriture connue dans applyPass, uniquement parmi les fenêtres de disposition. Passer ces IDs au runtime existant : cible finale dès le premier lot asynchrone, tandis que les autres cadres gardent leur animation. Pas d’AX synchrone nouveau sur main.
Réutiliser Pending et le minuteur TickScheduler pour au plus3reprises de découverte espacées50ms après création/activation sans commande. Une passe qui place quelque chose clôt les reprises. Aucun retry sur simple focus ou mouvement, aucun nouvel observateur/minuteur. Les suspensions et notifications concurrentes gardent la priorité.
Tests avant code : toute écriture de la nouvelle fenêtre égale la cible ; voisine connue possède des intermédiaires ; reprises bornées, arrêt au placement et blocage souris. Puis essais natifs et installation signée, santé et preuves.
