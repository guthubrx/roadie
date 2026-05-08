# Evenements et Query API

Roadie expose deux surfaces complementaires :

- `events subscribe` : flux JSON Lines pour suivre les changements.
- `query` : lecture ponctuelle de l'etat courant.

## Evenements

```bash
./bin/roadie events subscribe --from-now --initial-state
```

Exemple de ligne :

```json
{
  "schemaVersion": 1,
  "id": "evt_001",
  "timestamp": "2026-05-08T14:07:01Z",
  "type": "window.focused",
  "scope": "window",
  "subject": { "kind": "window", "id": "12345" },
  "cause": "ax",
  "payload": {
    "windowID": "12345",
    "app": "Terminal"
  }
}
```

Options :

```bash
./bin/roadie events subscribe --from-now
./bin/roadie events subscribe --initial-state
./bin/roadie events subscribe --type window.focused
./bin/roadie events subscribe --scope rule
```

Semantique :

- sans `--from-now`, Roadie rejoue le journal puis suit les nouvelles lignes;
- avec `--from-now`, Roadie commence a la fin du journal courant;
- avec `--initial-state`, Roadie emet d'abord `state.snapshot`;
- les consommateurs doivent ignorer les champs inconnus.

## Catalogue utile

Fenetre :

- `window.created`
- `window.destroyed`
- `window.focused`
- `window.moved`
- `window.resized`
- `window.grouped`
- `window.ungrouped`

Layout :

- `layout.mode_changed`
- `layout.rebalanced`
- `layout.flattened`
- `layout.insert_target_changed`
- `layout.zoom_changed`

Rules :

- `rule.matched`
- `rule.applied`
- `rule.skipped`
- `rule.failed`

Commandes :

- `command.received`
- `command.applied`
- `command.failed`

Control et securite :

- `config.reload_requested`
- `config.reload_applied`
- `config.reload_failed`
- `config.active_preserved`
- `restore.snapshot_written`
- `restore.crash_detected`
- `restore.crash_completed`
- `transient.detected`
- `transient.cleared`
- `transient.recovery_attempted`
- `layout_identity.restore_started`
- `layout_identity.restore_applied`
- `layout_identity.conflict_detected`
- `layout.width_adjust_requested`
- `layout.width_adjust_applied`
- `layout.width_adjust_rejected`

## Query API

```bash
./bin/roadie query state
./bin/roadie query windows
./bin/roadie query displays
./bin/roadie query desktops
./bin/roadie query stages
./bin/roadie query groups
./bin/roadie query rules
./bin/roadie query health
./bin/roadie query events
./bin/roadie query config_reload
./bin/roadie query restore
./bin/roadie query transient
./bin/roadie query identity_restore
```

Format stable :

```json
{
  "kind": "state",
  "data": {}
}
```

Cas d'usage :

- `query windows` : afficher les fenetres tileables dans une barre.
- `query groups` : afficher les groupes tabbed/stack.
- `query rules` : verifier ce qui est charge depuis TOML.
- `query health` : integrer Roadie dans un check local.
- `query events` : debugger les derniers evenements sans suivre le flux live.
- `query restore` : inspecter le dernier snapshot restore safety.
- `query transient` : inspecter l'etat de pause lie aux fenetres transitoires.
- `query identity_restore` : inspecter le dry-run de persistance layout v2.

## Exemple SketchyBar ou script

```bash
./bin/roadie events subscribe --from-now --type window.focused |
while read -r line; do
  app=$(printf '%s' "$line" | jq -r '.payload.app // "-"')
  echo "Focused app: $app"
done
```
