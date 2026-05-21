# Plan d'implémentation — SPEC-011 Composants atomiques

## Architecture cible

```
                                          ┌──────────────────────────┐
                                          │ roadied (binaire unique) │
                                          └────────────┬─────────────┘
                                                       │ dispatch par 1er arg
        ┌──────────┬──────────┬──────────┬─────────────┼─────────────┬───────────────┬───────────┐
        ▼          ▼          ▼          ▼             ▼             ▼               ▼           ▼
     run         tiler      rail      border       focus-mouse  titlebar-menu   target-mode  restore-safety
   (legacy   (LayoutMaint.)(RailCtrl.)(BorderCtrl.)(FocusCtrl.) (TitlebarCtrl.) (TargetCtrl.)  (RSC + watch)
    tout
    en un)
        │          │          │          │             │             │               │           │
        │          └──────────┴──────────┴──── lit/écrit ────┴─────────────┴───────────────┴───────────┘
        │                                          │
        │                              ~/.roadies/ (stages.json, events.jsonl,
        │                                          intent.json, <comp>.pid)
        │
        └─── instancie tous les contrôleurs comme aujourd'hui (rétro-compat)
```

## Étapes

### Étape 1 — Lock PID partagé (T001-T004)

**Fichier nouveau** : `Sources/RoadieDaemon/ComponentLockFile.swift`

API publique :
```swift
public struct ComponentLockFile {
    public init(component: String)
    public func acquire() throws        // crée ~/.roadies/<component>.pid avec le PID courant
    public func release()                // supprime le fichier au shutdown
    public static func isAlive(component: String) -> Int32?  // retourne PID si vivant, nil sinon
    public static func registry() -> [(component: String, pid: Int32, startedAt: Date)]
}
```

Comportement `acquire()` :
- Si fichier inexistant : créer avec PID courant
- Si fichier existant, PID vivant (`kill(pid, 0) == 0`) : `throw ComponentLockError.alreadyRunning(pid:)`
- Si fichier existant, PID mort (`kill(pid, 0) == -1 && errno == ESRCH`) : écraser
- Installer un handler SIGTERM/SIGINT qui appelle `release()` avant exit

### Étape 2 — Sous-commande dispatch (T005-T010)

**Fichier modifié** : `Sources/roadied/main.swift`

- Étendre le `switch args.first` avec les nouveaux cas : `tiler`, `rail`, `border`, `focus-mouse`, `titlebar-menu`, `target-mode`, `restore-safety`.
- Chaque branche :
  1. Lock PID via `ComponentLockFile`
  2. Démarrer le contrôleur correspondant (avec ses args spécifiques)
  3. Démarrer `NSApplication.shared.run()` (sauf composants purement timer qui restent `RunLoop.main`)
  4. Au signal, release lock

### Étape 3 — Flags `--no-*` pour le mode `run` (T011-T015)

**Fichier modifié** : `Sources/roadied/main.swift`

Ajout de flags symétriques aux `--no-rail` et `--no-restore-safety` existants :
- `--no-tiler` : ne pas instancier `LayoutMaintainer` ni le `MaintenanceTimerTarget`
- `--no-border` : ne pas instancier `BorderController`
- `--no-focus-mouse` : ne pas instancier `FocusFollowsMouseController`
- `--no-titlebar-menu` : ne pas instancier `TitlebarContextMenuController`
- `--no-target-mode` : ne pas instancier `TargetModeRuntimeController`

Le `printUsage()` est mis à jour pour documenter les nouveaux flags et sous-commandes.

### Étape 4 — Query components (T016-T018)

**Fichier modifié** : `Sources/RoadieDaemon/AutomationQueryService.swift`

Ajout du case `"components"` dans `query(_:)` qui appelle `ComponentLockFile.registry()` et retourne un `AutomationPayload.array` typé.

**Fichier modifié** : `Sources/RoadieCore/AutomationSnapshot.swift` (nouvelle struct ?)

Décision : pas de nouvelle struct fortement typée dans Core, on retourne du `AutomationPayload` brut depuis `AutomationQueryService` — c'est cohérent avec les autres queries (state, windows, etc.) qui encodent leurs structs respectives.

### Étape 5 — Tests (T019-T024)

**Fichiers nouveaux** :
- `Tests/RoadieDaemonTests/ComponentLockFileTests.swift` : acquire/release, double-lock, PID stale, cleanup
- `Tests/RoadieDaemonTests/ComponentSubcommandTests.swift` : dispatch des sous-commandes (test des parsers, pas du run loop)
- `Tests/RoadieDaemonTests/AutomationQueryComponentsTests.swift` : payload de `query components` avec et sans composants actifs

### Étape 6 — Script orchestration (T025-T026)

**Fichier nouveau** : `Scripts/start-modular`

Bash script qui lance chaque composant dans une session tmux dédiée. Pattern identique à `Scripts/start` mais multiplie les tmux sessions.

**Documentation** : `specs/011-atomic-components/quickstart.md` (guide rapide d'usage des nouveaux modes).

## Considérations constitutionnelles

| Article                          | Application                                                                   |
|----------------------------------|-------------------------------------------------------------------------------|
| **I — Langue française**         | Doc + commentaires en français, identifiants en anglais (consistance Swift)   |
| **III — SpecKit obligatoire**    | Cette spec ✓                                                                  |
| **IV — Disjoncteur**             | Implémentation par tâches atomiques + tests, max 3 tentatives par bug         |
| **VII — ADR**                    | Décision D2/D3/D5 candidate ADR si questions architecturales émergent         |
| **XV — Test-Before-Next**        | Chaque tâche T0XX → swift build + tests ciblés avant commit                   |
| **XVI — Worktree**               | `.worktrees/011-atomic-components/` si refactor large ; sinon main direct     |
| **XVII — DevKMS**                | Capturer pattern `ComponentLockFile` (réutilisable cross-projets)             |
| **XVIII — Complexité algo**      | Pas de boucle hot path nouvelle. `registry()` = O(n_components) avec n ≤ 8    |

## Critères de PR ready

- [ ] `swift build` OK avec PATH Xcode
- [ ] `swift test` 252+ tests passants (252 baseline + ~12 nouveaux)
- [ ] `roadied run --yes` démarre exactement les mêmes composants qu'avant SPEC-011 (SC-004)
- [ ] `roadie query components` retourne la liste attendue après chaque sous-commande
- [ ] Lock PID propre au shutdown (vérifier que `~/.roadies/<comp>.pid` est supprimé)
- [ ] Scripts existants `Scripts/start` / `Scripts/stop` non modifiés
- [ ] Spec, plan, tasks, research synchronisés
