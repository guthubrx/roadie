# Validation 094

- Tests : `Spec094WebGridTests` (5) ; suite complète 2 115 tests / 295 suites réussis.
- Installé : PID 63793, santé 5/5, certificat `roadied-cert`.
- Non vérifié : passage réel au navigateur (FR-002), non lancé pendant l'utilisation de l'écran par
  l'utilisateur ; à confirmer à son essai par l'événement `launcher.follow_browser` (`focused=true` :
  fenêtre de l'onglet trouvée). Délai d'attente de 450 ms choisi, non mesuré.
- Limite : un navigateur qui n'était pas ouvert peut ne pas avoir encore de fenêtre après 450 ms ;
  Roadie ne fait alors rien de plus (la fenêtre suit les règles de placement habituelles).
- Preuves : pas de diaporama (effet visible non rejoué, écran utilisé par l'utilisateur).
