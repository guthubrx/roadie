# ADR-001 — AX Observer par application, sans SkyLight ni SIP

**Date** : 2026-05-01 | **Statut** : Accepté

## Contexte

Le daemon doit observer les events fenêtre macOS en temps réel : création, destruction, déplacement, resize, focus. Deux options :

1. **yabai-style** : combiner `AXObserver` (par app) + notifications SkyLight `SLSRequestNotificationsForWindows` (privées, nécessitent injection scripting addition dans Dock.app, donc SIP partiellement désactivé).
2. **AeroSpace-style** : `AXObserver` par app uniquement, avec `Task { @MainActor }` pour synchroniser. Pas de SkyLight, pas de SIP off.

## Décision

**Option 2 (AeroSpace-style) avec un ajout** : abonnement à `kAXApplicationActivatedNotification` en plus des events fenêtre standards. Cet ajout (absent d'AeroSpace original) corrige le bug click-to-focus sur Electron/JetBrains.

Concrètement :
- Pour chaque `NSRunningApplication`, créer un thread dédié avec `CFRunLoop`.
- `AXObserverCreate` + 6 notifications : `kAXWindowCreatedNotification`, `kAXWindowMovedNotification`, `kAXWindowResizedNotification`, `kAXFocusedWindowChangedNotification`, `kAXUIElementDestroyedNotification`, **`kAXApplicationActivatedNotification`**.
- Dans le callback, `Task { @MainActor in ... }` pour dispatcher vers la machine d'état.

## Conséquences

### Positives

- **Pas de dépendance SIP** → installation triviale, pas de procédure complexe.
- **Pas de scripting addition** → robustesse face aux mises à jour macOS.
- **Click-to-focus fiable** sur les apps Electron/JetBrains (différenciateur vs AeroSpace).
- **Code Swift moderne** avec Concurrency, lisible et testable.

### Négatives

- Pas d'accès aux events SkyLight (ordering changes, etc.) → certaines régressions yabai connues seront difficiles à reproduire si elles dépendent de ces events. Acceptable pour le périmètre V1.
- Un thread par app peut sembler coûteux en théorie — en pratique, ces threads sont en attente passive sur leur RunLoop, coût mémoire ~64 KB/thread.

## Alternatives rejetées

- **Polling périodique** (100 ms) : consommation batterie inacceptable, latence visible.
- **Notification distribuée NSWorkspace seule** : trop pauvre, ne couvre pas window-level events.
- **Hybride yabai+AeroSpace** : complexité disproportionnée.

## Références

- yabai : `src/application.c` — `application_observe()`
- AeroSpace : `Sources/AppBundle/tree/MacApp.swift`, `Sources/AppBundle/util/AxSubscription.swift`
- research.md §1 (event loop) et §4 (click-to-focus)
