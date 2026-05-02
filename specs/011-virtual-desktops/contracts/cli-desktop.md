# Contract — CLI `roadie desktop *`

**Spec** : SPEC-011 | **Phase** : 1 | **Date** : 2026-05-02

Toutes les commandes communiquent avec `roadied` via le socket Unix `~/.roadies/daemon.sock`. Format wire : JSON-lines, une requête `{"cmd": "...", "args": {...}}`, une réponse `{"ok": true|false, "data": {...}, "error": {...}}`.

## `roadie desktop list`

Liste les desktops virtuels et leur état.

**Exit code** : 0 si succès, 1 si daemon indisponible.

**Stdout** (format human-readable par défaut) :

```
ID  LABEL    CURRENT  RECENT  WINDOWS  STAGES
1   code     *                 5        2
2   comm              *        3        1
3   web                        0        1
4   (none)                     0        1
...
```

**`--json`** : sortie JSON-lines, un desktop par ligne :

```json
{"id":1,"label":"code","current":true,"recent":false,"windows":5,"stages":2}
{"id":2,"label":"comm","current":false,"recent":true,"windows":3,"stages":1}
```

**Erreurs** :
- `multi_desktop_disabled` : si `[desktops] enabled = false` → exit 2 + stderr message clair.

---

## `roadie desktop focus <selector>`

Bascule vers le desktop indiqué.

**Selectors acceptés** :
- `1`..`N` (N = count) : par numéro
- `<label>` : par nom (si labelisé)
- `prev` : desktop précédent (cyclique)
- `next` : desktop suivant (cyclique)
- `recent` : desktop précédemment courant (= `roadie desktop back`)
- `first` / `last`

**Comportement** :
- No-op si selector résolu == currentID **et** `back_and_forth = false`.
- Bascule vers `recentID` si selector résolu == currentID **et** `back_and_forth = true` (FR-006).

**Exit code** : 0 succès, 2 selector invalide, 3 daemon indisponible.

**Stdout (succès)** :

```
focused: 2
```

**Stdout (`--json`)** :

```json
{"ok":true,"current_id":2,"previous_id":1,"event_emitted":true}
```

**Stdout (no-op)** :

```json
{"ok":true,"current_id":1,"previous_id":1,"event_emitted":false}
```

**Stderr (selector invalide)** :

```
roadie: unknown desktop selector: "foo"
```

---

## `roadie desktop current`

Affiche le desktop courant.

**Stdout** :

```
1 code
```

**`--json`** :

```json
{"id":1,"label":"code","windows":5,"active_stage_id":1}
```

---

## `roadie desktop label <name>`

Pose ou retire un label sur le desktop courant.

**Args** :
- `<name>` : alphanumérique + `-_`, max 32 chars. Vide ou absent → retire le label.

**Exit code** : 0 succès, 2 label invalide.

**Stdout** :

```
desktop 3 labeled as "comm"
```

**Validation** :
- Match regex `^[a-zA-Z0-9_-]{0,32}$`
- Pas de label "réservé" (`prev`, `next`, `recent`, `first`, `last`, `current`).

**Stderr** :

```
roadie: invalid label "this is too long": alphanumeric + '-_' only, max 32 chars
```

---

## `roadie desktop back`

Bascule vers le desktop précédemment courant. Équivalent strict à `roadie desktop focus recent`.

**Exit code** : 0 succès, 2 si pas de `recentID`.

**Stderr (pas de recent)** :

```
roadie: no recent desktop
```

---

## Erreur globale `multi_desktop_disabled`

Si `[desktops] enabled = false` dans `roadies.toml`, **toutes** les commandes `desktop.*` retournent :

```
exit 2
stderr: roadie: multi_desktop disabled, set [desktops] enabled = true in ~/.config/roadies/roadies.toml
```

Les commandes `stage.*` continuent de fonctionner sur l'unique desktop par défaut (id 1).

---

## Format wire JSON (socket Unix)

### Requête `desktop.focus`

```json
{"cmd":"desktop.focus","args":{"selector":"2"}}
```

### Réponse succès

```json
{"ok":true,"data":{"current_id":2,"previous_id":1,"event_emitted":true}}
```

### Réponse erreur

```json
{"ok":false,"error":{"code":"unknown_desktop","message":"unknown desktop selector \"foo\""}}
```

### Codes d'erreur normalisés

| Code | Description |
|---|---|
| `multi_desktop_disabled` | Feature désactivée par config |
| `invalid_argument` | Argument manquant ou mal formé |
| `unknown_desktop` | Selector ne résout pas vers un desktop existant |
| `invalid_label` | Label invalide (regex, longueur, réservé) |
| `daemon_unavailable` | Socket non joignable |
| `internal_error` | Erreur côté daemon (state corrompu, etc.) |
