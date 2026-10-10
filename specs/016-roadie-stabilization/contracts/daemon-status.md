# Contrat : `~/.roadies/daemon-status.json`

Écrit par le daemon (`run` ou `tiler`) au démarrage, puis toutes les 30 s et à chaque changement de permission ou de validité de config. Écriture atomique, sans réécriture si inchangé hors horodatage (l'horodatage `updatedAt` est mis à jour au plus toutes les 30 s).

```json
{
  "version": 1,
  "pid": 12345,
  "mode": "run",
  "roadieVersion": "0.3.0",
  "startedAt": "2026-10-10T20:00:00Z",
  "updatedAt": "2026-10-10T20:05:00Z",
  "accessibilityTrusted": true,
  "screenRecordingGranted": false,
  "config": { "valid": true, "path": "~/.config/roadies/roadies.toml", "error": null },
  "socketPath": "~/.roadies/roadied.sock"
}
```

`roadie doctor` considère le daemon arrêté si le pid n'est pas vivant ou si `updatedAt` a plus de 90 s.
