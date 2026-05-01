# CLI Contract — `stage`

**Feature** : 001-stage-manager | **Phase** : 1 | **Date** : 2026-05-01

Ce document est le contrat d'interface utilisateur du binaire `stage`. Toute déviation est un bug.

---

## Synopsis

```
stage <N>
stage assign <N>
```

Avec `N ∈ {1, 2}`.

Aucune option en flag (`--verbose`, `-h`, etc.) au-delà du strict nécessaire (cf. principe F constitution projet). Si une option est ajoutée plus tard, mettre à jour ce contrat.

---

## Sous-commandes

### `stage <N>` — bascule

Rend visibles les fenêtres assignées au stage `N` et masque celles assignées aux autres stages.

**Préconditions** :
- Permission Accessibility accordée
- `N ∈ {1, 2}`
- Optionnellement, `~/.stage/N` existe (s'il n'existe pas, c'est traité comme un stage vide)

**Effets** :
1. Chaque fenêtre listée dans `~/.stage/N` voit son attribut `kAXMinimizedAttribute` mis à `false` (dé-minimisée).
2. Chaque fenêtre listée dans `~/.stage/<autre>` (où `autre ≠ N`) voit son attribut `kAXMinimizedAttribute` mis à `true` (minimisée).
3. Les `cgWindowID` qui n'apparaissent plus dans `CGWindowListCopyWindowInfo` sont retirés des fichiers de stage (auto-GC, FR-006).
4. `~/.stage/current` est mis à jour avec la valeur de `N`.

**Sortie standard** : vide (FR-009).

**Sortie erreur** : une ligne par fenêtre disparue retirée (`window <wid> from stage <N> no longer exists, pruned`), une ligne par erreur AX rencontrée.

**Codes de sortie** :
| Code | Cas |
|---|---|
| 0 | Succès — bascule complète, aucune erreur (mais peut avoir auto-pruné des entrées) |
| 1 | Erreur runtime générique (échec lecture/écriture fichier d'état, AXError inattendue) |
| 2 | Permission Accessibility manquante |
| 64 | Argument invalide (N hors {1,2}, mauvais usage) |

**Idempotence** : si `current = N` et qu'on rappelle `stage N`, l'opération est ré-exécutée intégralement (re-minimise les autres stages, redéminimise N, re-prune). Pas d'optimisation court-circuit. Effet final identique.

---

### `stage assign <N>` — assignation

Inscrit la fenêtre frontmost dans le stage `N`. La retire des autres stages si elle y figure.

**Préconditions** :
- Permission Accessibility accordée
- `N ∈ {1, 2}`
- Une application est au premier plan ET cette application a une fenêtre focalisée

**Effets** :
1. Récupère la frontmost window via `NSWorkspace.frontmostApplication` → `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute` → `_AXUIElementGetWindow`.
2. Construit le `WindowRef = (pid, bundleID, cgWindowID)`.
3. Si `cgWindowID` figure dans un autre fichier de stage, le retire de ce fichier.
4. Ajoute le `WindowRef` au fichier `~/.stage/N` (si pas déjà présent).
5. Crée `~/.stage/` (mode 0755) s'il n'existe pas.

**Effets non-effectués** : la fenêtre n'est ni minimisée ni dé-minimisée. Sa visibilité reste celle qu'elle a au moment de l'assignation. La bascule effective ne se produit qu'au prochain `stage <N>`.

**Sortie standard** : vide (FR-009).

**Sortie erreur** : message explicite si :
- aucune frontmost application
- frontmost application sans fenêtre focalisée
- échec de récupération du `CGWindowID` (AXError)

**Codes de sortie** :
| Code | Cas |
|---|---|
| 0 | Succès |
| 1 | Erreur runtime (pas de frontmost, AXError, échec écriture) |
| 2 | Permission Accessibility manquante |
| 64 | Argument invalide |

---

## Autres invocations

### Sans argument ou avec un argument inconnu

```
stage
stage 3
stage foo
stage assign
stage assign 0
```

**Effet** : aucun. Le binaire imprime sur stderr la ligne d'usage et exit 64.

**Format usage** :
```
usage: stage <1|2>
       stage assign <1|2>
```

### `stage --help` / `-h`

**Effet** : non supporté (principe F : pas de flags). Comportement : traité comme argument inconnu, exit 64.

Si un utilisateur veut comprendre le binaire, il lit `quickstart.md` ou le code source (150 lignes).

---

## Comportements transverses

### Vérification permission

**Toujours en premier**, avant tout parsing d'argument. Si `AXIsProcessTrusted()` retourne `false` :

```
stage : permission Accessibility manquante.
Ouvre Réglages Système → Confidentialité et sécurité → Accessibilité,
ajoute le binaire (chemin : <argv[0] résolu en absolu>) et coche-le.
```

Exit 2.

### Création de `~/.stage/`

Création paresseuse au premier `assign`. Pas de commande `init` séparée.

### Format du fichier d'état corrompu

Une ligne mal-formée (champs manquants, `pid` non numérique, `cgWindowID` non numérique) est loguée :

```
stage : ligne ignorée dans ~/.stage/<N> (corrompue) : <ligne brute>
```

L'outil **continue** son opération avec les lignes valides restantes. Code de sortie 0 si l'opération réussit globalement.

---

## Tests d'acceptation associés

| Test shell | Cible |
|---|---|
| `tests/01-permission.sh` | Comportement sans Accessibility |
| `tests/02-assign.sh` | `stage assign 1`, vérification `~/.stage/1` |
| `tests/03-switch.sh` | `stage 1` puis `stage 2`, vérification visibilité fenêtres |
| `tests/04-disappeared.sh` | Tolérance fenêtres disparues |
| `tests/05-corrupt.sh` | Tolérance fichier corrompu (ajouté implicitement par cas FR-008 / D5) |

Note : un 5e test est ajouté pour couvrir le cas "fichier corrompu" qui n'avait pas son script dédié dans le plan initial. À intégrer dans `tasks.md`.

---

## Garanties de stabilité du contrat

Toute évolution du contrat (ajout d'option, changement de code de sortie, modification du format d'erreur) constitue une **breaking change** et nécessite :
1. Une nouvelle spec SpecKit
2. Justification dans `plan.md` Complexity Tracking
3. Pas de mode "rétrocompatibilité" — les utilisateurs sont eux-mêmes (suckless)
