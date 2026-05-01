# Research — Multi-desktop awareness (SPEC-003)

**Date** : 2026-05-01
**Status** : Final

Recherche technique sur la détection des desktops macOS sans SIP désactivé, la persistance par desktop, et le pattern d'observation cohérent avec V1.

---

## Décision 1 — Observer le desktop courant

**Décision** : utiliser `NSWorkspace.activeSpaceDidChangeNotification` (AppKit public) comme déclencheur principal, et `CGSGetActiveSpace(cid)` (SkyLight privée stable, lecture seule) pour récupérer l'identifiant `CGSSpaceID`.

**Rationale** :
- `NSWorkspace.activeSpaceDidChangeNotification` est **public et stable depuis macOS 10.6**. Aucune API privée pour la détection elle-même → robustesse maximale.
- `CGSGetActiveSpace` est nécessaire car `NSWorkspace` ne donne pas l'identifiant numérique du space, juste l'événement "ça a changé". L'identifiant est requis pour cross-référencer avec `CGSCopyManagedDisplaySpaces` qui contient les UUID.
- Yabai et AeroSpace utilisent ce pattern depuis des années, validé sur Sonoma/Sequoia/Tahoe.

**Alternatives considérées** :
- **Polling sur `CGSGetActiveSpace`** toutes les 100 ms : rejeté (CPU gaspillé, latence > observer).
- **`CGSAddSpaceObserver` (callback C privé)** : plus direct mais nécessite une indirection via `CGSConnectionID` plus fragile entre versions macOS. La voie `NSWorkspace` + `CGSGetActiveSpace` lecture est plus propre.
- **AppleScript via `osascript`** : trop lent (~50-100 ms par call).

---

## Décision 2 — Récupérer l'UUID stable d'un desktop

**Décision** : utiliser `CGSCopyManagedDisplaySpaces(cid)` qui retourne un CFArray ; chaque entrée représente un display physique et contient un sub-array `Spaces`, chacun avec une clé `uuid` (string) et une clé `id64` (numeric, = `CGSSpaceID`). Cross-référencer le `CGSSpaceID` actif avec ce tableau pour obtenir l'UUID.

**Rationale** :
- L'UUID est **stable entre redémarrages tant que le desktop n'est pas détruit par l'utilisateur** (crucial pour la persistance).
- L'index volatile (1, 2, 3…) change si l'utilisateur réordonne via Mission Control → l'UUID est l'ancrage logique.
- yabai utilise ce même mécanisme dans `space.c`.

**Alternatives considérées** :
- **Persister par index** (1, 2, 3) : fragile car réordonnancement utilisateur.
- **Persister par "label" macOS** : labels macOS Mission Control n'existent pas via API publique.

---

## Décision 3 — Pattern de persistance par desktop

**Décision** : 1 fichier TOML par UUID de desktop dans `~/.config/roadies/desktops/<uuid>.toml`. Écriture atomique (temp + rename). Lecture lazy au switch in (charge uniquement le desktop d'arrivée). Pas de cache mémoire des desktops non-actifs.

**Rationale** :
- TOML cohérent avec le reste du projet (config + stages V1).
- 1 fichier par desktop = isolation totale, corruption d'un desktop n'affecte pas les autres.
- Lecture lazy = empreinte mémoire constante, indépendante du nombre de desktops.
- Écriture atomique = pas de fichier partiel en cas de crash daemon.

**Alternatives considérées** :
- **Un seul fichier `desktops.toml`** avec dict `[uuid]` : risque de corruption globale, lock contention.
- **SQLite** : surdimensionné pour ce volume (≤ 50 KB par desktop), introduit une dépendance.
- **JSON** : moins lisible/éditable manuellement par l'utilisateur.

---

## Décision 4 — Migration V1 → V2 (compat ascendante)

**Décision** : au boot V2, si `~/.config/roadies/stages/` existe (V1) et `~/.config/roadies/desktops/` n'existe pas (V2 jamais activé), déplacer tous les fichiers `~/.config/roadies/stages/*.toml` vers `~/.config/roadies/desktops/<current-desktop-uuid>.toml` en les fusionnant. Garder `~/.config/roadies/stages/` en backup nommé `~/.config/roadies/stages.v1-backup-YYYYMMDD/`.

**Rationale** :
- Migration automatique sans demander à l'utilisateur (FR-023).
- Backup pour rollback si l'utilisateur veut revenir à V1.
- Mapping au desktop courant au moment du boot = comportement le plus prévisible (l'utilisateur démarre roadie, il est sur un desktop, ses stages V1 s'y rattachent).

**Alternatives considérées** :
- **Demander à l'utilisateur** quel desktop est cible : friction inutile, le résultat sera le même 99 % du temps.
- **Mapper à tous les desktops** : crée des duplicatas. Mauvaise idée.

---

## Décision 5 — Window pinning desktop (FR-024)

**Décision** : **DEFER en V3**. Le scope V2 est restreint à l'observation et la persistance par desktop. Pas de manipulation programmatique de `kAXSpaceID`.

**Rationale** :
- `kAXSpaceID` est **read-only via AX** sans SIP off. Impossible de déplacer une fenêtre vers un autre desktop par programmation propre.
- Workarounds (faire `AXUIElementPerformAction` sur le menu Window→Move to Desktop) sont fragiles, app-spécifiques, non testables automatiquement.
- yabai a la même limitation et l'expose explicitement.
- Best-effort en V3 si demande utilisateur forte.

**Alternatives considérées** :
- **Implémenter en V2 best-effort** : ajout de complexité pour résultat inconsistant. Mauvais ROI vs autres features V2.

---

## Décision 6 — Format des events

**Décision** : JSON-lines (1 event = 1 ligne JSON) sur un canal subscription via le socket Unix existant. Commande `roadie events --follow` ouvre une connexion qui reste ouverte et reçoit les events au fil de l'eau.

**Format event** :
```json
{"event": "desktop_changed", "ts": "2026-05-01T13:42:51.832Z", "from": "uuid-A", "to": "uuid-B", "from_index": 1, "to_index": 2}
{"event": "stage_changed", "ts": "2026-05-01T13:43:00.123Z", "desktop_uuid": "uuid-B", "from": "stage1", "to": "stage2"}
```

**Rationale** :
- JSON-lines = grep/jq-friendly (cohérent avec les logs daemon).
- Réutilisation du socket Unix existant = pas de nouveau bind, pas de port à configurer.
- Subscription via flag custom = pas de polling, push real-time.

**Alternatives considérées** :
- **FIFO Unix nommée séparée** (`~/.roadies/events.fifo`) : nécessite de créer le fichier au boot, complexité supplémentaire.
- **WebSocket / SSE sur HTTP** : surdimensionné, ajoute Network framework HTTP server.
- **macOS NSDistributedNotificationCenter** : limité aux apps en GUI, pas pour clients shell.

---

## Décision 7 — Tests

**Décision** : protocol `DesktopProvider` qui abstrait `CGSGetActiveSpace` + `CGSCopyManagedDisplaySpaces`. Implémentation prod = `SkyLightDesktopProvider`. Implémentation test = `MockDesktopProvider` avec scénarios scriptés. Tests unitaires sur la logique de transition, persistance, migration. Tests d'intégration shell qui scriptent osascript pour Mission Control.

**Rationale** :
- Injection via protocol = testabilité sans mocker le runtime macOS.
- Cohérent avec le pattern V1 (`Tiler` protocol, `LayoutHooks`).
- Les tests d'intégration shell complètent là où XCTest ne peut pas (Mission Control vrai).

---

## Sources externes consultées

- [yabai/space.c](https://github.com/koekeishiya/yabai/blob/master/src/space.c) — référence pour `CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace`, observer pattern
- [Apple AppKit `NSWorkspace.activeSpaceDidChangeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/1525953-activespacedidchangenotification) — public, stable
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) — n'utilise PAS Mission Control natif, mais le code C wrapping de SkyLight reste utile pour comparaison
- [CGS reverse-engineered headers (private)](https://github.com/NUIKit/CGSInternal) — déclarations communes utilisées par yabai/AeroSpace/Hammerspoon

---

## Risques résiduels & mitigations

| Risque | Probabilité | Mitigation |
|---|---|---|
| Apple casse `CGSGetActiveSpace` dans macOS 27+ | Faible (10 ans de stabilité) | Fallback graceful : log warning au boot, désactiver multi_desktop, retomber sur V1 |
| `NSWorkspace.activeSpaceDidChangeNotification` ne fire pas pour tous les types de transition | Possible (gestures swipe vs Mission Control button) | Polling de safety toutes les 2s en complément (non bloquant, juste si observer rate) |
| Migration V1→V2 corrompt les stages V1 | Faible si écriture atomique + backup | Backup horodaté avant migration, rollback documenté |
| Performance dégradée à grand nombre de desktops | Faible (écriture lazy, ≤ 50 KB/desktop) | SC-003 testé jusqu'à 10×10 ; au-delà, charge utilisateur atypique |
