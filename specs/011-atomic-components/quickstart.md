# Quickstart — Composants atomiques SPEC-011

## Trois modes d'invocation

### 1. Mode legacy (rétro-compatible)

```bash
./Scripts/start
# ou directement :
roadied run --yes
```

Démarre tous les composants dans un seul process (comportement historique).

### 2. Mode legacy avec exclusion ciblée

```bash
roadied run --yes --no-tiler --no-focus-mouse
```

Démarre tous les composants **sauf** ceux exclus. Idéal si tu veux désactiver
ponctuellement un composant qui te gêne sans renoncer aux autres.

Flags disponibles :
- `--no-tiler`              (LayoutMaintainer + AX live observer)
- `--no-rail`               (RailController)
- `--no-border`             (BorderController)
- `--no-focus-mouse`        (FocusFollowsMouseController)
- `--no-titlebar-menu`      (TitlebarContextMenuController)
- `--no-target-mode`        (TargetModeRuntimeController)
- `--no-restore-safety`     (RestoreSafetyService)

### 3. Mode atomique — un composant par process

```bash
./Scripts/start-modular
```

Lance chaque composant dans une session tmux séparée, avec son propre PID file
et ses propres logs. Tu peux killer/relancer chaque composant indépendamment.

Sous-commandes disponibles :

| Commande                  | Composant lancé                       |
|---------------------------|---------------------------------------|
| `roadied tiler --yes`     | LayoutMaintainer seul (polling layout)|
| `roadied rail`            | RailController seul                   |
| `roadied border`          | BorderController seul                 |
| `roadied focus-mouse`     | FocusFollowsMouseController seul      |
| `roadied titlebar-menu`   | TitlebarContextMenuController seul    |
| `roadied target-mode`     | TargetModeRuntimeController seul      |
| `roadied restore-safety`  | RestoreSafetyRuntimeController seul   |

Chaque sous-commande pose un lock `~/.roadies/<composant>.pid`. Si tu relances
deux fois la même sous-commande, la seconde refuse avec
`roadied <composant>: already running (pid N)`.

## Inspection

```bash
roadie query components
```

Retourne un JSON listant les composants actifs (par PID file vivant) avec leur
PID et leur timestamp de démarrage.

Exemple :
```json
{
  "kind": "components",
  "data": [
    { "component": "rail", "pid": 12345, "startedAt": "2026-05-10T14:30:00Z" },
    { "component": "border", "pid": 12346, "startedAt": "2026-05-10T14:30:01Z" }
  ]
}
```

## Cas d'usage

### Rail seul (sans tiler)

```bash
roadied rail
```

Idéal si tu préfères le floating natif macOS mais veux garder le rail comme
navigation visuelle entre stages. Le rail réagit aux clics et déclenche les
changements de stage (le CLI fait le hide/show côté Accessibility, cf. audit
SPEC-002).

### Tiler sans rail

```bash
roadied tiler --yes
```

Le polling layout tourne, mais aucune UI rail/border/menu. Utile en headless
CI ou pour tests d'intégration ciblés.

### Killer un composant sans toucher aux autres

```bash
# Via tmux (mode modular) :
tmux kill-session -t roadie-rail

# Via PID :
kill $(cat ~/.roadies/rail.pid)
```

Les autres composants continuent normalement.

## Garanties

- **Rétro-compatibilité totale** : `Scripts/start` et `roadied run --yes` non
  modifiés dans leur comportement.
- **Atomicité par lock PID** : un composant lancé deux fois échoue avec un
  message clair.
- **Pas de cascade au crash** : tuer un composant ne tue pas les autres ; les
  fichiers d'état restent cohérents grâce au verrou EventLog SPEC-002.
- **Logs séparés** : chaque session tmux a son `~/.roadies/<nom>.stdout.log`
  et `~/.roadies/<nom>.stderr.log`.
