# Contrat CLI : Roadie Control & Safety

## Reload de config

```bash
roadie config reload [--json]
```

**Succes JSON**:

```json
{
  "status": "applied",
  "path": "~/.config/roadies/roadies.toml",
  "version": "sha256:...",
  "applied_at": "2026-05-08T16:00:00Z"
}
```

**Erreur JSON**:

```json
{
  "status": "failed_keeping_previous",
  "path": "~/.config/roadies/roadies.toml",
  "error": "invalid rules[2].match.app_regex",
  "active_version": "sha256:..."
}
```

## État Control Center

```bash
roadie control status --json
```

Retourne `ControlCenterState`.

## Restore safety

```bash
roadie restore snapshot --json
roadie restore apply [--yes] [--json]
roadie restore watcher status --json
```

`restore apply` est idempotent et best-effort.

## Fenêtres transitoires

```bash
roadie transient status --json
```

Retourne le dernier `TransientWindowState` connu.

## Layout persistence v2

```bash
roadie state identity inspect --json
roadie state restore-v2 --dry-run --json
roadie state restore-v2 --yes --json
```

Le dry-run liste les matches, scores et conflits sans modifier l'etat.

## Width presets/nudge

```bash
roadie layout width preset next
roadie layout width preset prev
roadie layout width nudge +0.05
roadie layout width nudge -0.05
roadie layout width set 0.67
roadie layout width all 0.8
```

**Erreur structuree** si le layout actif n'est pas compatible :

```json
{
  "status": "rejected",
  "reason": "unsupported_layout",
  "layout": "float"
}
```
