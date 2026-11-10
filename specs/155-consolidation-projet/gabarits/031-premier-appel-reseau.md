# ADR031 - Premier appel réseau : vérification de mise à jour

Statut : accepté, le 10 novembre 2026. Session155.

## Contexte
Roadie ne faisait aucun appel réseau : aucun fichier de `Sources/` n'utilisait `URLSession`. Pour savoir si une version plus récente existe, l'utilisateur ouvrait la page des releases à la main. Roadie lit des données privées (titres de fenêtres, fichiers, signets). Un appel réseau est donc un changement de nature, à borner.

## Décision
Une seule commande fait un appel réseau : `roadie update check`. Elle s'exécute dans le processus `roadie`, jamais dans le daemon `roadied`. L'appel part seulement quand l'utilisateur lance la commande. Roadie ne vérifie rien en arrière-plan, ni au démarrage, ni à intervalle régulier.

L'appel est `GET https://api.github.com/repos/guthubrx/roadie/releases/latest`, sans jeton. Les seuls en-têtes ajoutés sont `Accept: application/vnd.github+json` et `User-Agent: roadie-update-check`. La session est éphémère : ni cache, ni cookie. Le délai est de 5 secondes ; la commande rend la main en 6 secondes au plus.

La commande compare deux numéros de version par une fonction pure, `ReleaseCheck.isNewer`. Elle affiche le résultat et l'adresse de la release. Elle ne télécharge rien et n'installe rien.

## Conséquences
- L'utilisateur sait en une commande si sa version est à jour.
- GitHub voit l'adresse IP du poste, comme pour toute visite de la page des releases. Aucune donnée de l'utilisateur n'est envoyée.
- Sans réseau, la commande échoue avec le code 1 et un message. Le reste de Roadie ne dépend pas du réseau.
- GitHub limite les appels sans jeton par adresse IP. Un appel manuel reste loin de cette limite.
- Tout nouvel appel réseau demande une nouvelle décision. Contrôle : `grep -rn "URLSession" Sources/` ne doit citer que `Sources/RoadieDaemon/ReleaseCheck.swift`.

## Alternatives rejetées
- Sparkle (mise à jour automatique) : nouvelle dépendance, clé de signature et flux à héberger.
- Vérification au démarrage du daemon : appel réseau sans action de l'utilisateur.

## Sources
- `specs/155-consolidation-projet/research.md`, R12.
- `specs/155-consolidation-projet/contracts/cli.md`, section 4.
