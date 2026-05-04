# Contract — IPC public Unix-socket (FROZEN par SPEC-024)

**Statut** : figé. Toute violation = breaking change = nouvelle SPEC explicite requise.
**Source de vérité** : implémentation actuelle dans `Sources/RoadieCore/Server.swift` + `Sources/roadied/CommandRouter.swift`.

Cette spec **garantit zéro modification** observable du contrat IPC public sur `~/.roadies/daemon.sock`. Le présent document fige le contrat dans son état pré-migration et constitue le critère de non-régression pour SC-004 et FR-008.

## Endpoint

- **Type** : Unix domain socket (`AF_UNIX`)
- **Path** : `~/.roadies/daemon.sock`
- **Protocole** : JSON-lines (1 requête JSON terminée par `\n`, 1 réponse JSON terminée par `\n`)
- **Mode** : `0700` (utilisateur courant uniquement)

## Schéma requête / réponse

### Requête

```json
{"command": "<verb>.<object>", "args": {"<key>": "<value>", ...}}
```

### Réponse synchrone

```json
{"ok": true, "data": {...}}      // succès
{"ok": false, "error": "..."}    // erreur
```

### Souscription events (mode push)

Requête : `{"command": "events.subscribe"}`

Réponse initiale : `{"ok": true, "subscribed": true}`

Puis stream de lignes JSON, une par event :

```json
{"event": "stage_changed", "from": "1", "to": "2", "desktop_id": "1", "ts": 1714780800000}
{"event": "desktop_changed", "from": "1", "to": "2", "from_label": "main", "to_label": "comm", "ts": ...}
{"event": "window_created", "wid": 12345, "pid": 622, "bundle": "com.googlecode.iterm2", "ts": ...}
...
```

## Liste des commandes publiques (figée)

Énumération exhaustive. Pas de retrait, pas d'ajout, pas de renommage par cette spec.

### Stage

- `stage.list` (avec optionnellement `args.display`, `args.desktop`)
- `stage.switch` (`args.stage_id`, optionnellement `args.display`)
- `stage.assign` (`args.stage_id`, `args.wid?`, `args.display?`)
- `stage.create` (`args.name`, `args.display?`)
- `stage.rename` (`args.stage_id`, `args.new_name`)
- `stage.delete` (`args.stage_id`)

### Desktop

- `desktop.list`
- `desktop.current`
- `desktop.focus` (`args.desktop_id` | `args.label` | `args.direction`)
- `desktop.label` (`args.desktop_id`, `args.label`)

### Window

- `windows.list` (verbe pluriel — figé tel quel)
- `window.thumbnail` (`args.wid`)
- `window.display` (`args.wid`, `args.display_id`)
- `window.space` (`args.wid`, `args.desktop_id`) — si module SPEC-010 chargé
- `window.stick`, `window.pin` — si module chargé

### Display

- `display.list`
- `display.current`
- `display.focus` (`args.display_id` | `args.direction`)

### Daemon

- `daemon.status` (`args.json?`)
- `daemon.reload`

### FX (modules SIP-off, optionnels)

- `fx.status`

### Events

- `events.subscribe` (passe en mode push, cf. ci-dessus)

### Tiling

- `tiling.reserve` (`args.edge`, `args.size`, `args.display_id?`)

## Codes de retour CLI

Le binaire CLI `roadie` (Sources/roadie/main.swift) traduit les réponses socket en codes Unix standard :

- `0` : succès
- `1` : erreur applicative (ex: stage introuvable, fenêtre périmée)
- `2` : erreur de connexion (daemon down)
- `3` : erreur de parsing args
- `4` : permission insuffisante (Accessibility manquante côté daemon)

Ces codes sont consommés par BTT, scripts shell, plugin SketchyBar.

## Format des sorties

Chaque commande a un format de sortie défini : tableau humain par défaut, JSON via `--json`. Les schémas restent figés.

## Garanties non fonctionnelles

- **Latence p95** ≤ 30 ms pour les requêtes synchrones courtes (stage.list, daemon.status)
- **Throughput events** ≥ 100 events/s soutenable
- **Aucune perte d'event** entre subscribe et unsubscribe (modulo timeout réseau, négligeable sur Unix-domain)

## Tests de non-régression (à exécuter post-migration)

Voir `quickstart.md` section "Tests de migration" pour la checklist exécutable.

```bash
# Sanity 1 — daemon répond
echo '{"command": "daemon.status"}' | nc -U ~/.roadies/daemon.sock

# Sanity 2 — events flow
echo '{"command": "events.subscribe"}' | nc -U ~/.roadies/daemon.sock &
# Déclencher un changement, observer un event JSON arriver

# Sanity 3 — CLI
roadie stage list --json
roadie desktop current
roadie display list

# Sanity 4 — thumbnail
roadie window thumbnail $(some_wid) > /dev/null  # doit pas timeout
```

Toute divergence = bug bloquant pour SPEC-024.
