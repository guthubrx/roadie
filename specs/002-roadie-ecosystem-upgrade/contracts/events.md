# Event Contract

## Format

Roadie publie des événements JSON Lines. Une ligne = un événement complet.

```json
{
  "schemaVersion": 1,
  "id": "evt_20260508_120000_0001",
  "timestamp": "2026-05-08T10:00:00Z",
  "type": "window.focused",
  "scope": "window",
  "subject": { "kind": "window", "id": "12345" },
  "correlationId": "cmd_abc123",
  "cause": "ax",
  "payload": {
    "windowId": "12345",
    "app": "Terminal",
    "title": "roadie"
  }
}
```

## Compatibility Rules

- Les consommateurs doivent ignorer les champs inconnus.
- Roadie ne renomme pas un `type` publié dans `schemaVersion=1`.
- Les nouveaux types peuvent être ajoutés sans changement de version.
- Une rupture de payload obligatoire impose une nouvelle version ou un nouveau type.

## Minimum Event Catalog

### Application

- `application.launched`
- `application.terminated`
- `application.activated`
- `application.hidden`
- `application.visible`

### Window

- `window.created`
- `window.destroyed`
- `window.focused`
- `window.moved`
- `window.resized`
- `window.minimized`
- `window.deminimized`
- `window.title_changed`
- `window.floating_changed`
- `window.grouped`
- `window.ungrouped`

### Display/Desktop/Stage

- `display.added`
- `display.removed`
- `display.focused`
- `desktop.changed`
- `desktop.created`
- `desktop.renamed`
- `stage.changed`
- `stage.created`
- `stage.hidden`
- `stage.visible`

### Layout

- `layout.mode_changed`
- `layout.rebalanced`
- `layout.flattened`
- `layout.insert_target_changed`
- `layout.zoom_changed`

### Rules

- `rule.matched`
- `rule.applied`
- `rule.skipped`
- `rule.failed`

### Commands

- `command.received`
- `command.applied`
- `command.failed`
- `config.reloaded`

## Subscription Semantics

`roadie events subscribe` doit :

- écrire sur stdout en `jsonl`.
- supporter `--from-now` pour ignorer l'historique.
- supporter `--type <event-type>` répétable.
- supporter `--scope <scope>` répétable.
- supporter `--initial-state` pour émettre un événement synthétique `state.snapshot`.
- terminer proprement sur SIGINT sans corrompre le journal.
