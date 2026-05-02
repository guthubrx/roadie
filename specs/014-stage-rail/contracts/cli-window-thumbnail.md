# Contract — `roadie window thumbnail <wid>`

**Status**: Draft
**Spec**: SPEC-014 stage-rail
**Type**: Nouvelle commande IPC daemon (lecture seule + side-effect : observer SCK)

## Synopsis

```
roadie window thumbnail <wid>
```

Retourne les bytes PNG (base64) de la dernière vignette connue de la fenêtre `wid`. Si pas encore observée, le daemon démarre l'observation ScreenCaptureKit, retourne immédiatement la dernière vignette disponible (ou icône d'app en fallback) et continue d'émettre des `thumbnail_updated` events.

## Arguments

| Arg | Type | Description |
|---|---|---|
| `wid` | UInt32 | CGWindowID de la fenêtre cible |

## Pré-conditions

- Daemon `roadied` démarré.
- `wid` doit exister dans `WindowRegistry` (sinon erreur `wid_not_found`).
- Permission Screen Recording **recommandée** mais non obligatoire (fallback gracieux).

## Réponses

### Succès — vignette ScreenCaptureKit

```json
{
  "status": "ok",
  "data": {
    "png_base64": "iVBORw0KGgoAAAANSUhEUgAA...",
    "wid": 12345,
    "size": [320, 200],
    "degraded": false,
    "captured_at": "2026-05-02T17:30:42.123Z"
  }
}
```

### Succès dégradé — icône d'app (Screen Recording refusée)

```json
{
  "status": "ok",
  "data": {
    "png_base64": "iVBORw0KGgoAAAANSUhEUgAA...",
    "wid": 12345,
    "size": [128, 128],
    "degraded": true,
    "captured_at": "2026-05-02T17:30:42.123Z"
  }
}
```

### Erreur — wid inconnu

```json
{
  "status": "error",
  "code": "wid_not_found",
  "message": "window 12345 not in registry"
}
```

### Erreur — daemon trop chargé (très rare)

```json
{
  "status": "error",
  "code": "thumbnail_unavailable",
  "message": "thumbnail capture currently unavailable, retry"
}
```

## Side-effects

- Si la fenêtre n'était pas observée : démarrage d'un `SCStream` ScreenCaptureKit à 0.5 Hz.
- Inscription d'un timer de "dernière requête" : si pas d'appel pendant 30 s, le stream est arrêté pour économiser CPU/batterie.
- Cache LRU mis à jour (entrée déplacée en MRU).

## Garanties

- **Latence** : < 50 ms en cas de cache hit, < 500 ms si capture immédiate nécessaire (premier appel pour cette `wid`).
- **Ordering** : garanti monotone par `captured_at` (utile pour invalidation côté rail).
- **Idempotence** : N appels successifs sur la même `wid` à < 1s d'intervalle retournent la **même** vignette (pas de double capture).

## CLI examples

```bash
# Récupérer la vignette d'une fenêtre via le client roadie
roadie window thumbnail 12345

# Décoder en PNG
roadie window thumbnail 12345 | jq -r '.data.png_base64' | base64 -d > thumb.png

# Test rapide via socat
echo '{"cmd":"window.thumbnail","wid":12345}' | nc -U ~/.roadies/daemon.sock
```

## Test acceptance (bash)

`tests/14-thumbnail-roundtrip.sh` :
1. Lancer `roadied`.
2. Ouvrir une fenêtre Terminal.
3. `roadie window thumbnail <wid>` → décoder `png_base64` → vérifier signature PNG (8 magic bytes `89 50 4E 47 0D 0A 1A 0A`).
4. Vérifier `degraded` cohérent avec l'état de la permission Screen Recording.
5. Vérifier `size` ≤ 320×200.
