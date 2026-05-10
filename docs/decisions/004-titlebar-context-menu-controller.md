# Decision : controleur AppKit global pour menu de barre de titre

## Contexte

Roadie doit proposer des actions de rangement de fenetre sans imposer a l'utilisateur de connaitre un ID de fenetre. Le clic droit dans la zone haute d'une fenetre est un geste naturel, mais il ne doit pas voler les menus contextuels du contenu applicatif.

## Decision

Le controleur AppKit observe les clics droits et effectue un hit-test strict :

- fonctionnalite desactivee par defaut;
- fenetre Roadie geree requise;
- fenetre tileable requise par defaut;
- zone haute limitee par `height`;
- marges gauche/droite exclues pour proteger les boutons et toolbars.

Si un critere echoue, Roadie ne consomme pas le clic.

## Consequences

- Le comportement est reversible par TOML.
- Les popups et dialogues restent proteges par la politique de tiling.
- Les actions du menu revalident l'etat courant avant mutation.
- Le controleur ne rajoute pas de polling dans le chemin focus/bordure.
