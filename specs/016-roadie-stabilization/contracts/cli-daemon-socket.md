# Contrat : canal CLI vers daemon

**Socket** : `~/.roadies/roadied.sock` (Unix domain, `SOCK_STREAM`, permissions `0600`, créé sous `umask 0177`).
**Serveur** : `roadied run` et `roadied tiler` (un seul, grâce au verrou d'instance `~/.roadies/roadied.lock`), via `CommandSocketServer.start(router:)`.
**Version de protocole** : `1`.

## Requête

Une ligne JSON terminée par `\n`, 64 Kio au plus :

```json
{"version":1,"argv":["focus","left"],"cwd":"/Users/x"}
```

`cwd` sert seulement à résoudre une valeur relative de `--config`.

## Réponse

Une ligne JSON terminée par `\n`, puis fermeture :

```json
{"version":1,"exitCode":0,"stdout":"...","stderr":""}
```

## Commandes routées vers le daemon (liste explicite)

Seules des commandes finies, sans boucle AppKit ni flux continu :

- `focus`, `move`, `warp` (alias `wrap`), `resize`
- `stage`, `desktop`, `display`, `window` (dont `window swap`)
- `layout`, `rules`, `query`
- `restore unhide-all`
- `state dump`, `state audit` (lecture)

Toute autre commande s'exécute toujours dans le processus `roadie`, en particulier : `events subscribe` (flux continu), `targets` et `grid` (overlays et mode interactif), `record`, `daemon *`, `doctor`, `permissions`, `config *`, `help`, `-h`, `--help`, `--version`. Une commande accompagnée de `--help` ou `-h` reste locale.

Le serveur refuse une commande hors liste avec `exitCode 64` ; le client ne l'envoie pas.

## Règles du serveur

- Lecture et écriture du socket sur une file dédiée, hors du fil principal ; délai de lecture et d'écriture 2 s ; requête de plus de 64 Kio refusée (`exitCode 64`).
- Seule l'exécution du router passe sur le fil principal (`DispatchQueue.main.sync`), une requête à la fois, dans le même ordre que les ticks : un seul écrivain d'état.
- Requête illisible : `exitCode 64`. `version` différente : `exitCode 70`.
- Au démarrage, un fichier de socket périmé est supprimé (le verrou d'instance garantit qu'aucun autre serveur ne l'utilise). À l'arrêt, le fichier est supprimé.

## Règles du client (`roadie`)

1. Commande hors liste : exécution locale.
2. Le client teste le verrou d'instance : `flock(LOCK_SH | LOCK_NB)` sur `~/.roadies/roadied.lock`. S'il réussit (verrou relâché aussitôt) ou si le fichier n'existe pas, le daemon est absent : exécution locale, sans message.
3. Si le verrou est tenu, le daemon est présent et la commande ne s'exécute JAMAIS en local :
   - connexion impossible en 0,5 s ou requête non transmise : `exitCode 69` avec un message explicite ;
   - réponse avec une `version` différente : `exitCode 69` (redémarrer le daemon) ;
   - requête transmise sans réponse lisible en 5 s : `exitCode 75` (la commande peut encore s'exécuter).
4. Sinon, le client recopie `stdout`, `stderr` et `exitCode` de la réponse.
