# OSAX IPC Protocol — daemon ↔ `roadied.osax`

**Date** : 2026-05-01

Spécification du protocole entre `OSAXBridge` (côté daemon, dans `RoadieFXCore.dylib`) et la scripting addition `roadied.osax` injectée dans Dock.

---

## Transport

- **Type** : socket Unix domain (SOCK_STREAM)
- **Path** : `/var/tmp/roadied-osax.sock`
- **Mode** : `0600` (owner-only)
- **Owner** : utilisateur courant (vérifié via `getuid()` côté osax au accept)

---

## Cycle de vie

### Côté osax

1. Au chargement par Dock (via `tell app "Dock" to load scripting additions`) → `+[ROHooks load]` (constructor Cocoa)
2. Crée socket `/var/tmp/roadied-osax.sock` (unlink si existe, bind, listen 4)
3. Démarre thread `accept` dédié (NSThread)
4. Pour chaque connexion entrante :
   - Vérifie `getsockopt(SO_PEERCRED)` ou `getpeereid()` → UID match owner uid → sinon close + log
   - Démarre thread reader sur la socket
   - Lit JSON-lines, dispatch chaque commande sur `dispatch_get_main_queue()` (CGS calls doivent être sur le main thread Dock)
   - Renvoie l'ack JSON-line dès que la commande est traitée

### Côté daemon (`OSAXBridge`)

1. `connect()` : essaie d'ouvrir le socket
   - Échec (`ENOENT`, `ECONNREFUSED`) → log info "osax not loaded yet", retry async toutes les 2 s
   - Succès → état `connected`
2. `send(cmd)` : sérialise en JSON, write socket, await ack
   - Si déco pendant write → enqueue, retry après reconnect
3. `disconnect()` : clean shutdown, ferme socket

---

## Format wire

Chaque ligne = 1 JSON object terminé par `\n`. Pas de framing supplémentaire.

### Requête (daemon → osax)

```jsonc
{"cmd": "noop"}
{"cmd": "set_alpha", "wid": 12345, "alpha": 0.7}
{"cmd": "set_shadow", "wid": 12345, "density": 0.0}
{"cmd": "set_blur", "wid": 12345, "radius": 30}
{"cmd": "set_transform", "wid": 12345, "scale": 0.95, "tx": 10, "ty": 0}
{"cmd": "set_level", "wid": 12345, "level": 24}
{"cmd": "move_window_to_space", "wid": 12345, "space_uuid": "550e8400-e29b-41d4-a716-446655440000"}
{"cmd": "set_sticky", "wid": 12345, "sticky": true}
```

### Réponse (osax → daemon)

```jsonc
{"status": "ok"}
{"status": "error", "code": "wid_not_found"}
{"status": "error", "code": "unknown_command", "message": "cmd 'foo' not supported"}
```

**Ordre garanti** : 1 requête → 1 réponse, dans l'ordre. Pas de pipelining out-of-order pour V1.

---

## Codes d'erreur stables

| Code | Sens | Action daemon |
|---|---|---|
| `wid_not_found` | La fenêtre `wid` n'existe plus côté CGS | Log info, suppr animations en cours sur ce wid |
| `unknown_command` | Commande non listée dans le contrat | Log error (bug dans le module) |
| `invalid_parameter` | Param hors range (alpha < 0, etc.) | Log error (bug dans le module) |
| `cgs_failure` | CGS API a retourné un code d'erreur inconnu | Log warning, ignore (l'effet visuel ne sera pas appliqué) |
| `permission_denied` | UID mismatch détecté | Log critical (bug archi ou attaque) |
| `bridge_disconnected` | Côté daemon : osax disconnect pendant attente ack | Retry après reconnect |

---

## Heartbeat

Le daemon DOIT envoyer un `noop` toutes les 30 s pour vérifier la connexion. Si pas de réponse en 5 s → présume disconnect, ferme socket, retry async.

```swift
// dans OSAXBridge
private func startHeartbeat() {
    Task {
        while isConnected {
            try? await Task.sleep(for: .seconds(30))
            let result = await send(.noop, timeout: .seconds(5))
            if case .error(let code, _) = result, code == "bridge_disconnected" {
                await reconnect()
            }
        }
    }
}
```

---

## Sémantique des commandes

### `noop`

Heartbeat / ping. Retourne `{"status": "ok"}`. Aucun effet de bord.

### `set_alpha`

Applique `CGSSetWindowAlpha(connID, wid, alpha)` côté Dock avec sa connexion master.

- `alpha` ∈ [0.0, 1.0]
- Effet immédiat (pas de transition côté osax — les animations sont gérées par `AnimationLoop` côté daemon qui spam des `set_alpha` à 60 FPS)
- Erreur si `wid` n'existe pas → `wid_not_found`

### `set_shadow`

Applique `CGSSetWindowShadowAndRimParameters(connID, wid, density, ...)` ou variante équivalente.

- `density` ∈ [0.0, 1.0] (0 = ombre invisible, 1 = défaut macOS)
- Le `rim` (cadre lumineux) reste à valeur par défaut

### `set_blur`

Applique `CGSSetWindowBackgroundBlurRadius(connID, wid, radius)`.

- `radius` ∈ [0, 100]
- 0 = pas de blur, ~30 = effet glass typique

### `set_transform`

Applique `CGSSetWindowTransform(connID, wid, transform)` avec `CGAffineTransform`.

- `scale` : facteur multiplicatif (1.0 = neutre)
- `tx` / `ty` : translation en points (0 = neutre)
- Transform combiné = `scale × translate`. Pas de rotation supportée (pas demandée pour les animations Roadie).

### `set_level`

Applique `CGSSetWindowLevel(connID, wid, level)`.

- `level` ∈ [-2000, 2000] (NSWindowLevel int)
- Utilisé pour overlay borders (SPEC-008) et always-on-top (SPEC-010)

### `move_window_to_space`

Combo `CGSRemoveWindowsFromSpaces` + `CGSAddWindowsToSpaces`.

- `space_uuid` doit correspondre à un Space existant (cross-référencé via SPEC-003)
- Erreur si UUID invalide → `invalid_parameter`
- Erreur si `wid` introuvable → `wid_not_found`

### `set_sticky`

Applique le flag `kCGSStickyWindowFlag` via `CGSSetWindowEventMask` (yabai pattern).

- `sticky: true` → fenêtre apparaît sur tous les desktops
- `sticky: false` → comportement normal (un seul desktop)

---

## Sécurité

1. **UID match** au accept : le client connecté DOIT avoir le même UID que l'utilisateur owner du Dock injecté. Si mismatch → close + log critical.
2. **Validation params** : chaque commande valide ses params côté osax avant CGS call. Out-of-range = `invalid_parameter`.
3. **Pas de root** : l'osax tourne dans Dock (process user). Pas d'élévation privilège possible.
4. **Throttle** : si une commande est envoyée plus de 1000 fois / seconde sur le même `wid+property`, log warning (signe de bug ou animation runaway côté module). Pas de drop hard, juste signalisation.

---

## Tests

### Côté osax

- Test indépendant (script bash) : ouvrir manuellement la socket via `nc -U /var/tmp/roadied-osax.sock`, envoyer `{"cmd": "noop"}\n`, vérifier `{"status": "ok"}`
- Test de stress : 10 000 commands `set_alpha` sur fenêtres existantes en 10 s, vérifier que Dock ne crash pas + p99 latence < 300 ms
- Test malformé : envoyer JSON invalide → osax doit `error: invalid_parameter`, pas crash

### Côté daemon

- Mock socket dans `OSAXBridgeTests` : simule reply ok / error / disconnect, vérifier comportement queue
- `tests/integration/12-fx-loaded.sh` : end-to-end avec stub module qui envoie `noop` et vérifie ack
