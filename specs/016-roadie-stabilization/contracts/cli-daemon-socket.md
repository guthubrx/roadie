# Contrat : canal CLI vers daemon

**Socket** : `~/.roadies/roadied.sock` (Unix domain, `SOCK_STREAM`, permissions `0600`).
**Serveur** : `roadied run` et `roadied tiler` (un seul, grâce au verrou d'instance).

## Requête

Une ligne JSON terminée par `\n` :

```json
{"version":1,"argv":["focus","left"],"cwd":"/Users/x","env":{"ROADIE_JSON":"0"}}
```

## Réponse

Une ligne JSON terminée par `\n`, puis fermeture :

```json
{"version":1,"exitCode":0,"stdout":"...","stderr":""}
```

## Règles

- Le client attend au plus 2 s la connexion et 10 s la réponse. En cas d'échec de connexion, il exécute la commande en local (repli) sans message.
- Commandes toujours locales : `daemon start|stop|restart|health`, `doctor`, `permissions`, `--help`, `--version`, `config validate`.
- Le serveur traite les requêtes une par une sur le fil principal (même ordre que les ticks), ce qui garantit un seul écrivain.
- `version` différente : le serveur répond `exitCode 70` et le client se replie en local.
