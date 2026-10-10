# ADR-007 : La CLI passe par le daemon via un socket local

## Statut

Accepté. Mis en oeuvre par la SPEC-016 (contrat : `specs/016-roadie-stabilization/contracts/cli-daemon-socket.md`).

## Contexte

Chaque appel à `roadie` démarrait un processus complet. Ce processus lisait lui-même les fenêtres par Accessibility, calculait un snapshot, puis écrivait les fichiers d'état. Trois problèmes en découlaient :

- La CLI avait besoin de la permission Accessibilité. BetterTouchTool, Karabiner ou skhd, qui lancent la CLI, devaient donc aussi l'obtenir.
- Chaque raccourci clavier payait un scan complet des fenêtres, ce qui rendait les raccourcis lents.
- Deux processus (le daemon et la CLI) écrivaient les mêmes fichiers d'état en même temps. Cela causait des mises à jour perdues (voir l'ADR-008).

## Décision

Le daemon (`roadied run` ou `roadied tiler`) ouvre un socket Unix `~/.roadies/roadied.sock` (permissions `0600`). La CLI y envoie une ligne JSON par requête (`{"version":1,"argv":[...]}`) et lit une ligne JSON en réponse (`exitCode`, `stdout`, `stderr`).

- La logique de commande vit dans `RoadieDaemon` (`CLICommandRouter`). Elle écrit dans des tampons au lieu d'appeler `print` et `exit`.
- Le daemon traite les requêtes une par une, dans le même ordre que ses ticks. Un seul processus écrit donc l'état.
- Si le socket est absent ou ne répond pas dans les 2 secondes, `roadie` exécute la commande en local. Le comportement reste correct sans daemon.
- Ces commandes restent toujours locales : `daemon start|stop|restart|health`, `doctor`, `permissions`, `config validate`, `--help`, `--version`.
- Si la version du protocole diffère, le serveur répond `exitCode 70` et la CLI se replie en local.

## Conséquences positives

- La CLI n'a plus besoin de la permission Accessibilité quand le daemon tourne. Les outils de raccourcis n'ont rien à autoriser.
- Une commande ne déclenche plus de scan complet : elle réutilise l'état du daemon.
- Un seul écrivain pour les commandes, ce qui réduit les conflits sur les fichiers d'état.

## Conséquences négatives

- Un nouveau protocole à maintenir et à versionner.
- Une commande lente dans le daemon retarde les suivantes, car la file est sérielle. Le délai de 10 s côté client borne l'attente.
- Le repli local garde deux chemins d'exécution à tester.

## Alternatives rejetées

- `DistributedNotificationCenter` : pas de réponse ni de code de retour.
- XPC : exige un bundle et un service enregistré, ce qui ne convient pas à une installation par `make install`.

## Garde-fous

- Ne jamais faire dépendre `daemon start`, `doctor` ou `permissions` du socket : ils servent justement quand le daemon est en panne.
- Ne jamais élargir les permissions du socket au-delà de `0600`.
