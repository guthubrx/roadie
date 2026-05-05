# CLI Contracts — SPEC-026

## Nouvelles commandes

### `roadie tiling balance`

**Effet** : réinitialise tous les `adaptiveWeight` des leaves du tree courant (current stage + display) à 1.0. Déclenche un `applyLayout()` immédiat.

**Args** : aucun.

**Sortie** : `{"status":"ok","leaves_balanced":N}` (JSON sur stdout) ou `{"status":"error","reason":"..."}` (JSON sur stderr, exit code != 0).

**Exit codes** : 0 OK ; 2 daemon down ; 3 stage manager désactivé.

**Idempotence** : oui. Tree vide ou single-leaf → `{"leaves_balanced":0}`, exit 0.

---

### `roadie tiling rotate <angle>`

**Effet** : tourne récursivement le tree.
- 90 : inverse orientation H↔V à chaque container.
- 180 : inverse l'ordre des children à chaque container.
- 270 : combine 90 + 180.

**Args** : `<angle>` ∈ {90, 180, 270}.

**Sortie** : `{"status":"ok","angle":N}` ou erreur.

**Exit codes** : 0 OK ; 1 angle invalide ; 2 daemon down.

**Idempotence** : 360° de rotations cumulées doivent ramener le tree à l'identique (testé).

---

### `roadie tiling mirror <axis>`

**Effet** : inverse l'ordre des children pour tous les containers de l'orientation correspondante.
- `x` → containers H (inverse left↔right).
- `y` → containers V (inverse top↔bottom).

**Args** : `<axis>` ∈ {x, y}.

**Sortie** : `{"status":"ok","axis":"x|y"}` ou erreur.

**Exit codes** : 0 OK ; 1 axis invalide ; 2 daemon down.

**Idempotence** : 2 mirrors successifs sur le même axe ramènent à l'identique.

---

### `roadie scratchpad toggle <name>`

**Effet** :
- Si scratchpad pas lancé : exécute `cmd` async, attache 1ère wid matchant.
- Si scratchpad visible : cache (offscreen via HideStrategy.corner).
- Si scratchpad caché : restore à dernière position visible.

**Args** : `<name>` (string, doit matcher un `[[scratchpads]] name = ...`).

**Sortie** : `{"status":"ok","state":"spawning|visible|hidden","wid":N}` ou erreur.

**Exit codes** : 0 OK ; 4 scratchpad name not configured ; 5 spawn timeout (rapporté async, pas bloquant).

## Commandes existantes — pas de changement contractuel

Les autres commandes `roadie tiling.*`, `roadie focus.*`, `roadie stage.*` restent inchangées.

## Routing daemon

Le `CommandRouter.swift` ajoute les cases :
- `"tiling.balance"` → délégation à `LayoutEngine.balance()`
- `"tiling.rotate"` → `LayoutEngine.rotate(angle:)`
- `"tiling.mirror"` → `LayoutEngine.mirror(axis:)`
- `"scratchpad.toggle"` → `ScratchpadManager.toggle(name:)`

Les commandes `daemon.reload` existantes propagent automatiquement les nouvelles clés TOML (focus_follows_mouse, mouse_follows_focus, smart_gaps_solo) aux composants concernés.
