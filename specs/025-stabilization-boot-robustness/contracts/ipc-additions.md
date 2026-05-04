# IPC Additions — SPEC-025

**Statut** : additions au contrat figé SPEC-024 (`ipc-public-frozen.md`).
**Compat** : strictement additif. Aucune commande existante modifiée.

## Nouvelle commande : `daemon.health`

### Requête

```json
{"version": "roadie/1", "command": "daemon.health"}
```

### Réponse

```json
{
  "ok": true,
  "data": {
    "total_wids": 8,
    "offscreen_at_restore": 0,
    "zombies_purged": 0,
    "drifts_fixed": 0,
    "verdict": "healthy"
  }
}
```

### Sémantique

- `total_wids` : compteur instantané au moment de la requête
- `offscreen_at_restore` : valeur capturée au dernier boot (n'est pas recalculée)
- `zombies_purged` / `drifts_fixed` : valeurs cumulées depuis le dernier boot
- `verdict` ∈ `{healthy, degraded, corrupted}` selon ratio `(touched / total) > 30%`

### CLI

```bash
roadie daemon health           # output texte
roadie daemon health --json    # output JSON
```

---

## Nouvelle commande : `daemon.heal`

### Requête

```json
{"version": "roadie/1", "command": "daemon.heal"}
```

### Réponse

```json
{
  "ok": true,
  "data": {
    "purged": 2,
    "drifts_fixed": 1,
    "wids_restored": 0,
    "duration_ms": 185
  }
}
```

### Sémantique

- Idempotent — relancer 2× = pas de side effect
- Si déjà sain : tous les compteurs à 0, `duration_ms` court (~30 ms)
- Pas de mutation des `saved_frame` persistés (ne touche pas les TOML) — agit uniquement sur l'état runtime + tree

### CLI

```bash
roadie heal                    # output texte
roadie heal --json             # output JSON
```

Codes de retour CLI : `0` succès, `3` daemon down (cohérent avec autres commandes).

---

## Préservation contrat figé

Toutes les commandes listées dans SPEC-024 `contracts/ipc-public-frozen.md` continuent à fonctionner à l'identique :

- `stage.list/switch/assign/create/rename/delete`
- `desktop.list/current/focus/label`
- `windows.list`, `window.thumbnail`, `window.display`, `window.space`, `window.stick`, `window.pin`
- `display.list/current/focus`
- `daemon.status`, `daemon.reload`, `daemon.audit`
- `events.subscribe`
- `tiling.reserve`
- `fx.status`
- `rail.status`, `rail.toggle`, `rail.renderer.list`, `rail.renderer.set`

Aucune signature de payload modifiée. Aucun champ supprimé. Le test `scripts/test-ipc-contract-frozen.sh` (livré par SPEC-024) continue à passer 8/8 après cette spec.
