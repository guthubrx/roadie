# Research — Composants Roadie atomiques

## Approche hybride retenue

### Étape 1 — Baseline

L'audit SPEC-002 (`audits/2026-05-10/session-2026-05-10-spec-002-01/scoring.md`) a documenté que les composants sont **logiquement indépendants** mais **couplés au démarrage** dans `Sources/roadied/main.swift`. Le `RailController`, `BorderController`, `FocusFollowsMouseController`, `TitlebarContextMenuController`, `TargetModeRuntimeController` ne consomment rien que `LayoutMaintainer` produirait — ils observent les fichiers d'état (`~/.roadies/*`).

### Étape 2 — Validation live (architectures dominantes des window managers macOS)

Comparatif rapide des approches d'atomicité :

| WM         | Modèle                          | Avantages                              | Inconvénients                          |
|------------|---------------------------------|----------------------------------------|----------------------------------------|
| **yabai**  | 1 binaire monolithique          | Simple, état centralisé                | Pas de désactivation par composant     |
| **AeroSpace** | 1 binaire + config TOML      | Désactivable via config                | Pas de sous-commandes lancement isolé  |
| **Hyprland** | 1 binaire + plugins .so       | Plugins dynamiques                     | Complexité de packaging                |
| **i3/sway**| 1 binaire + IPC socket          | IPC riche                              | Pas applicable macOS                   |
| **skhd**   | Binaire séparé pour hotkeys     | Atomicité forte                        | 2 binaires à orchestrer                |

Approche retenue pour Roadie : **modèle yabai + sous-commandes skhd-like dans un seul binaire**. Un seul exécutable `roadied`, plusieurs modes d'invocation (`run`, `tiler`, `rail`, `border`, `focus-mouse`, `titlebar-menu`, `target-mode`, `restore-safety`). Combine la simplicité de packaging de yabai et l'ergonomie ops de skhd.

### Étape 3 — Synthèse avec sources

**Red flags identifiés et mitigés** :

- **Race condition multi-process sur fichiers partagés** → résolu en SPEC-002 (R2, verrou NSLock `EventLog`). Cf. `Sources/RoadieDaemon/EventLog.swift:64`.
- **Double démarrage du même composant** → mitigé par lock PID `~/.roadies/<composant>.pid` (pattern Apple `launchctl`).
- **Drift d'état entre composants** → tous les composants relisent l'état depuis disk (`StageStore.state()`), pas de cache mémoire partagé. Le `RailController` watche déjà `stages.json` via DispatchSource (`Sources/RoadieDaemon/RailController.swift:62`).

**Recommandation** : implémenter d'abord les flags `--no-*` (faible coût, haut ROI, rétro-compat triviale), puis ajouter les sous-commandes pour les composants où le démarrage isolé apporte la plus grande valeur (rail, tiler).

## Décisions techniques

### D1 — Format des sous-commandes

`roadied <component> [args]` avec dispatch par nom (déjà le pattern utilisé pour `run`, `restore-watch`, `snapshot`, `permissions` dans `Sources/roadied/main.swift:29`).

### D2 — Run loop par composant

| Composant                       | Run loop nécessaire | Raison                                           |
|---------------------------------|---------------------|--------------------------------------------------|
| `LayoutMaintainer` (tiler)      | RunLoop.main        | Timer périodique + AX events                     |
| `RailController`                | NSApplication.run   | Fenêtres NSPanel + monitors NSEvent globaux      |
| `BorderController`              | NSApplication.run   | NSPanel/NSWindow overlay                         |
| `FocusFollowsMouseController`   | RunLoop.main        | Timer polling                                    |
| `TitlebarContextMenuController` | NSApplication.run   | NSEvent.addLocalMonitor + global monitor         |
| `TargetModeRuntimeController`   | NSApplication.run   | CGEvent tap + overlay                            |
| `RestoreSafetyService`          | RunLoop.main        | Timer polling                                    |

Décision : chaque sous-commande lance `NSApplication.shared.run()` après avoir initialisé son contrôleur. Les sous-commandes qui n'ont pas besoin de UI peuvent quand même utiliser NSApplication avec policy `.accessory` pour bénéficier du run loop unifié.

### D3 — Lock PID

Format : `~/.roadies/<component>.pid` contient un seul entier (PID). Au démarrage :
1. Lire le fichier ; si absent, écrire le PID courant.
2. Si présent, vérifier `kill(pid, 0)` ; si processus vivant → exit 1 avec message `roadied <component>: already running (pid <N>)`.
3. Si processus mort (PID stale), écraser et démarrer.
4. À l'arrêt propre (signal SIGTERM), supprimer le fichier.

Pattern identique au PID file existant `~/.roadies/roadied.pid` géré par `Scripts/start`/`Scripts/stop`.

### D4 — Inventory `query components`

Implémenter `roadie query components` dans `AutomationQueryService` (`Sources/RoadieDaemon/AutomationQueryService.swift:20`) :
- Lister les fichiers `~/.roadies/<component>.pid`
- Pour chaque PID, vérifier vivant via `kill(pid, 0)`
- Retourner `[{component, pid, startedAt, alive}]`

`startedAt` = mtime du fichier PID.

### D5 — Rétro-compatibilité `roadied run --yes`

Aucun changement de comportement. Le mode `run` continue à instancier tous les composants comme aujourd'hui. Les nouveaux flags `--no-tiler`, `--no-border`, `--no-focus-mouse`, `--no-titlebar-menu`, `--no-target-mode` sont **opt-out**, par défaut désactivés (donc composant **actif** par défaut, comme aujourd'hui).

### D6 — Scripts d'orchestration

Ajout d'un script `Scripts/start-modular` (optionnel) qui lance chaque composant dans une tmux session séparée. Le script existant `Scripts/start` reste inchangé pour ne pas casser les workflows.

## Risques

| Risque                                                             | Probabilité | Impact | Mitigation                                                                 |
|--------------------------------------------------------------------|-------------|--------|----------------------------------------------------------------------------|
| Lock PID stale après crash brutal                                  | Moyenne     | Faible | Vérification `kill(pid, 0)` au démarrage, écrasement si mort               |
| Régression rétro-compat sur `Scripts/start`                        | Faible      | Élevé  | Tests d'intégration smoke sur `roadied run --yes` + check `roadie query components` |
| Conflit double monitor NSEvent (rail + titlebar-menu indépendants) | Moyenne     | Moyen  | Chaque composant ouvre son propre monitor — pas de partage d'instance, déjà testé séparément en cycle 2 SPEC-002 |
| Verrouillage `EventLog` insuffisant pour multi-process             | Faible      | Élevé  | NSLock est in-process ; ajouter `flock()` au niveau fichier si besoin futur |

**Important** : le NSLock SPEC-002 (R2) est **in-process**. Quand plusieurs **process** roadied tournent en parallèle, le NSLock ne synchronise pas. Pour SPEC-011, cela impose soit :
- Accepter le risque (writes JSONL atomiques par event individuel : un event = 1 `write(2)` syscall typiquement = atomic POSIX si < PIPE_BUF)
- Ajouter `flock(LOCK_EX)` au-dessus du NSLock

Décision : Phase 1 accepte le risque (write atomique POSIX pour < ~4KB, typiquement le cas d'un event JSON sérialisé). Si on observe en cycle 2 de l'audit une corruption JSONL multi-process, ajouter `flock` en cycle 3.
