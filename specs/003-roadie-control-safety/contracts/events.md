# Contrat Événements : Roadie Control & Safety

Tous les evenements utilisent `RoadieEventEnvelope` schema version 1.

## Config

- `config.reload_requested`
- `config.reload_applied`
- `config.reload_failed`
- `config.active_preserved`

Payload minimal :

```json
{
  "path": "~/.config/roadies/roadies.toml",
  "version": "sha256:...",
  "error": "optional"
}
```

## Control Center

- `control_center.opened`
- `control_center.action_invoked`
- `control_center.settings_saved`
- `control_center.settings_failed`

## Restore safety

- `restore.snapshot_written`
- `restore.exit_started`
- `restore.exit_completed`
- `restore.crash_detected`
- `restore.crash_completed`
- `restore.failed`

## Fenêtres transitoires

- `transient.detected`
- `transient.cleared`
- `transient.recovery_attempted`
- `transient.recovery_failed`

## Layout persistence

- `layout_identity.snapshot_written`
- `layout_identity.restore_started`
- `layout_identity.restore_applied`
- `layout_identity.restore_skipped`
- `layout_identity.conflict_detected`

## Width adjustment

- `layout.width_adjust_requested`
- `layout.width_adjust_applied`
- `layout.width_adjust_rejected`

## Ajouts API Query

`roadie query events` doit pouvoir filtrer ces types. `roadie query state` doit exposer les derniers statuts config reload, transient window et restore safety.
