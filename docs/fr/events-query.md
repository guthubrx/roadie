# Evenements et Query API

Roadie expose deux surfaces complementaires :

- `events subscribe` : flux JSON Lines pour suivre les changements.
- `query` : lecture ponctuelle de l'etat courant.

## Evenements

```bash
roadie events subscribe --from-now --initial-state
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
roadie events subscribe --from-now
roadie events subscribe --initial-state
roadie events subscribe --type window.focused
roadie events subscribe --scope rule
```

Semantique :

- sans `--from-now`, Roadie rejoue le journal puis suit les nouvelles lignes;
- avec `--from-now`, Roadie commence a la fin du journal courant;
- avec `--initial-state`, Roadie emet d'abord `state.snapshot`;
- si des evenements ont pu etre perdus entre deux lectures (ancienne rotation du journal deja supprimee, journal tronque), Roadie emet `events.gap` avant la suite du flux, quels que soient les filtres; son `payload` donne `reason` (`rotated_generation_missing` ou `file_truncated`) et `lostAfterOffset`;
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

Restore safety :

- `restore.snapshot_written`
- `restore.apply_started`
- `restore.apply_completed`
- `restore.apply_failed`

Performance read-only :

- `performance.summary_requested`
- `performance.recent_requested`
- `performance.thresholds_requested`

Parking d'ecran :

- `display.parking_started`
- `display.parking_restored`
- `display.parking_ambiguous`
- `display.parking_noop`

Flux d'evenements :

- `events.gap`

Administration :

- `config.reloaded`
- `config.reload_failed`
- `layout.width_adjust_requested`
- `layout.width_adjust_applied`
- `layout.width_adjust_rejected`

Le catalogue public est aussi exposable par CLI :

```bash
roadie query event_catalog
```

## Query API

```bash
roadie query state
roadie query windows
roadie query displays
roadie query desktops
roadie query stages
roadie query groups
roadie query rules
roadie query health
roadie query events
roadie query event_catalog
roadie query performance
roadie query restore
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
- `query event_catalog` : lister les types d'evenements publics.
- `query performance` : lire un resume read-only construit depuis `events.jsonl`.
- `query restore` : inspecter le dernier snapshot restore.

## Exemple SketchyBar ou script

```bash
roadie events subscribe --from-now --type window.focused |
while read -r line; do
  app=$(printf '%s' "$line" | jq -r '.payload.app // "-"')
  echo "Focused app: $app"
done
```
