# Contrat — ComponentLockFile

## Emplacement des verrous

- Production : `~/.roadies/<component>.pid`
- Tests : `<NSTemporaryDirectory>/roadie-test-locks-<pid_processus_test>/<component>.pid`
  - Isolation par PID du process de test → pas de collision entre runs `swift test` parallèles
  - Nettoyage automatique au reboot (NSTemporaryDirectory)

## Format

Un seul entier (PID) suivi d'un saut de ligne. UTF-8.

```
12345
```

## Cycle de vie

```
acquire() → fichier inexistant → ÉCRIT PID courant
acquire() → fichier présent, PID vivant ≠ moi → THROW alreadyRunning(pid:)
acquire() → fichier présent, PID stale → ÉCRASE avec PID courant
release() → fichier appartient à moi → SUPPRIME
release() → fichier appartient à autre → NO-OP (anti-corruption)
release() → fichier absent → NO-OP
```

## Détection PID vivant

`kill(pid, 0)` :
- Renvoie 0 → process vivant
- Renvoie -1, errno ESRCH → stale
- Renvoie -1, errno EPERM → vivant mais pas autorisé à signaler (considéré vivant)

## Registry

`ComponentLockFile.registry()` parcourt `~/.roadies/*.pid`, filtre les stale, retourne triés par `component`. O(n_pid_files), n ≤ 8 dans Roadie (rail, tiler, border, focus-mouse, titlebar-menu, target-mode, restore-safety, run-legacy).

## Concurrence

Le fichier est écrit via `write(atomically: true)` → garanti atomique par le FS pour des écritures < taille bloc (~ infaillible pour un PID ASCII).

Deux acquire() concurrents sur le même composant peuvent en théorie tous deux réussir si timing < quelques µs. Mitigation : la première sous-commande qui démarre voit le PID file et exit immédiatement. Pour un vrai mutex inter-process, un `flock(LOCK_EX | LOCK_NB)` serait nécessaire — mais le pattern lance-une-fois suffit pour la cible (utilisateur lance manuellement ou via launchd qui dé-duplique).
