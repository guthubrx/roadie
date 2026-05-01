# Data Model — Stage Manager Suckless

**Feature** : 001-stage-manager | **Phase** : 1 | **Date** : 2026-05-01

---

## Entités

### `WindowRef`

Référence persistante vers une fenêtre macOS.

| Champ | Type | Source | Notes |
|---|---|---|---|
| `pid` | `pid_t` (int32) | `NSRunningApplication.processIdentifier` | Permet de retrouver l'`AXUIElement` de l'app |
| `bundleID` | `String` | `NSRunningApplication.bundleIdentifier` | Information de diagnostic uniquement (jamais clé primaire) |
| `cgWindowID` | `CGWindowID` (uint32) | `_AXUIElementGetWindow(axWindow)` | **Clé primaire**. Stable pour la durée de vie de la fenêtre |

**Sérialisation ligne** : `<pid>\t<bundleID>\t<cgWindowID>\n`
**Exemple** : `1234\tcom.apple.Terminal\t987654\n`

**Validation** :
- `pid > 0`
- `bundleID` non vide, sans TAB ni LF
- `cgWindowID > 0`
- Une ligne malformée (mauvais nombre de champs ou champ illisible) est loguée sur stderr et ignorée (FR edge case "fichier corrompu")

**Cycle de vie** :
- Créée par la commande `stage assign <N>` à partir de la frontmost window
- Retirée d'un fichier de stage par la même commande quand réassignée à un autre stage
- Retirée automatiquement à la prochaine bascule si son `cgWindowID` n'est plus présent dans `CGWindowListCopyWindowInfo` (auto-GC, FR-006)

---

### `Stage`

Collection ordonnée de `WindowRef`. Représentée par un fichier `~/.stage/<N>` où `N ∈ {1, 2}`.

**Opérations** :

| Opération | Signature conceptuelle | Effet |
|---|---|---|
| `read(N)` | `Int → [WindowRef]` | Lit le fichier, parse, retourne la liste. Fichier inexistant = liste vide. |
| `write(N, refs)` | `Int, [WindowRef] → Void` | Écriture atomique du fichier (via Foundation `String.write(toFile:atomically:)`) |
| `add(N, ref)` | `Int, WindowRef → Void` | Lit, ajoute si pas déjà présent, écrit |
| `remove(N, wid)` | `Int, CGWindowID → Bool` | Lit, retire ligne(s) matchant `wid`, écrit. Retourne `true` si une ligne a été retirée |
| `prune(N, alive)` | `Int, Set<CGWindowID> → Int` | Lit, retire toutes les lignes dont le `wid` n'est pas dans `alive`, écrit. Retourne le nombre de lignes retirées (auto-GC) |

**Invariant** : un même `cgWindowID` n'apparaît jamais simultanément dans `~/.stage/1` et `~/.stage/2`. Garanti par la commande `assign` qui retire d'abord puis ajoute, et par le fait que les `cgWindowID` sont uniques par macOS (pas de collision possible entre apps).

---

### `CurrentStage`

Marqueur scalaire du stage actuellement actif.

| Champ | Type | Stockage |
|---|---|---|
| `value` | `Int` (1 ou 2) | Fichier `~/.stage/current`, contient un seul caractère ASCII |

**Opérations** :
- `read()` : retourne `1` si fichier absent ou contenu invalide (default sain)
- `write(N)` : écrit "1" ou "2" en écriture atomique

**Mise à jour** : après chaque bascule réussie. Avant la mise à jour, l'opération de masquage/affichage est complète (même si auto-GC a retiré des entrées). En cas d'échec total de la bascule (toutes les fenêtres mortes), `current` est tout de même mis à jour : c'est le comportement attendu (le bureau apparaît vide).

---

## Diagramme de transitions

```
                           ┌──────────────┐
                           │ État initial │
                           │ ~/.stage/    │
                           │ inexistant   │
                           └──────┬───────┘
                                  │ stage assign 1
                                  ▼
        ┌───────────────────────────────────────┐
        │ ~/.stage/1 contient WindowRef(W1)     │
        │ ~/.stage/current = 1 (création)       │
        └────┬─────────────────────────────┬────┘
             │ stage 2 (bascule)           │ stage assign 2
             ▼                              ▼
    ┌──────────────────────┐    ┌─────────────────────────────────┐
    │ W1 minimisée         │    │ ~/.stage/1 vide (W1 retirée)    │
    │ ~/.stage/current = 2 │    │ ~/.stage/2 contient WindowRef(W1)│
    └──────────────────────┘    └─────────────────────────────────┘
```

---

## Conventions de fichiers

- Encodage : UTF-8 strict
- Fin de ligne : `\n` (LF), jamais `\r\n`
- Pas de BOM
- Permissions Unix : `0644` (lecture monde, édition utilisateur)
- Répertoire `~/.stage/` créé avec `0755` au premier `assign` si inexistant

---

## Notes d'implémentation

- Les types Foundation sont préférés (`String`, `URL`) plutôt que `[UInt8]` brut, car la lecture-écriture atomique de Foundation simplifie D7.
- Le parsing évite les regex : `String.split(separator:)` suffit et reste lisible.
- Aucune classe ni struct dédiée pour `Stage` : on manipule directement `[WindowRef]` et l'API ci-dessus est implémentée comme fonctions libres dans `stage.swift`. Un objet `Stage` formel violerait le principe A.
