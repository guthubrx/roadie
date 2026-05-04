# Data Model — SPEC-024 Migration mono-binaire

**Phase 1** | Date : 2026-05-04 | Branche : `024-monobinary-merge`

Cette spec ne crée aucune entité de données utilisateur. Elle modifie le **modèle d'instances runtime** : qui possède quoi, qui parle à qui, quels objets cessent d'exister.

## Entités runtime (avant / après)

### Daemon — process unifié `roadied`

| Entité | Présente V1 | Présente V2 | Notes |
|--------|-------------|-------------|-------|
| `Daemon` (RoadieCore/Server.swift) | ✓ | ✓ | Inchangé. Possède le tiling, stages, desktops, IPC server, cache thumbnails. |
| `StageManager` (RoadieStagePlugin) | ✓ | ✓ | Inchangé. |
| `Tiler` protocol + impls (RoadieTiler) | ✓ | ✓ | Inchangé. |
| `DesktopRegistry` (RoadieDesktops) | ✓ | ✓ | Inchangé. |
| `DesktopEventBus` (RoadieDesktops) | ✓ | ✓ étendu | Étendu pour porter les events stages/windows/displays/thumbnails (cf. R1). Reste un actor Swift avec AsyncStream subscribers. |
| `ThumbnailCache` (RoadieCore/ScreenCapture) | ✓ | ✓ | Inchangé. Désormais accessible aussi par `RailController` directement (en plus du serveur IPC). |
| `IPCServer` (RoadieCore/Server.swift) | ✓ | ✓ | Inchangé. Continue à servir CLI, SketchyBar, scripts externes. Subscribe au `DesktopEventBus` pour transmettre les events publics au format JSON-lines. |
| `RailController` (RoadieRail) | ⊘ (process séparé) | ✓ (in-process) | Devient une instance créée par le bootstrap du `Daemon`, vit dans le même process. |
| `StageRailPanel` × N écrans (RoadieRail/Views) | ⊘ | ✓ | Idem. |
| `EdgeMonitor`, `FadeAnimator`, `IconResolver`, etc. | ⊘ | ✓ | Idem. |

### Rail séparé `roadie-rail` (V1)

| Entité | Présente V1 | Présente V2 | Notes |
|--------|-------------|-------------|-------|
| `AppDelegate` (RoadieRail) | ✓ | ✗ supprimé | Logique de bootstrap/PID-lock fusionnée dans `Daemon.bootstrap()`. |
| `main.swift` (entry point) | ✓ | ✗ supprimé | Plus de produit `executable` "roadie-rail" dans Package.swift. |
| `RailIPCClient` (Networking) | ✓ | ✗ supprimé | Remplacé par accès in-process à `Daemon`. |
| `EventStream` (Networking) | ✓ | ✗ supprimé | Remplacé par `eventBus.subscribe()`. |
| `ThumbnailFetcher` (Networking) | ✓ | ✓ refactor | Devient une fine layer au-dessus de `ThumbnailCache.fetchOrCapture(wid:)`, plus de socket. |
| `RailState` (Models) | ✓ | ✓ | Reste owned par RailController, inchangé conceptuellement. |
| `StageVM`, `WindowVM` (Models) | ✓ | ✓ | Inchangés. Reçoivent leurs données via subscribe au bus. |
| `decodeBool/Int/String` helpers (RailController) | ✓ | ✗ supprimé | Plus nécessaire avec accès Swift typé. |

## Relations runtime (dépendances)

### V1 — process séparés

```text
launchd
  ├── roadied (process A)
  │     ├─ Daemon
  │     │  ├─ StageManager, Tiler, DesktopRegistry, ThumbnailCache, DesktopEventBus
  │     │  └─ IPCServer @ ~/.roadies/daemon.sock
  │     └─ FXLoader (modules SIP-off)
  │
  └── roadie-rail (process B, lancé manuellement ou via second LaunchAgent)
        └─ AppDelegate
           └─ RailController
              ├─ RailIPCClient ──→ socket Unix ──→ IPCServer (A)
              ├─ EventStream   ──→ socket Unix ──→ IPCServer (A)
              ├─ ThumbnailFetcher ──→ socket Unix ──→ IPCServer (A)
              ├─ EdgeMonitor (NSEvent global monitor)
              └─ N × StageRailPanel (NSPanel, par écran)
```

### V2 — process unifié

```text
launchd
  └── roadied (process unique, .accessory)
        ├─ Daemon
        │  ├─ StageManager, Tiler, DesktopRegistry, ThumbnailCache
        │  ├─ DesktopEventBus (actor) ◄──┐
        │  └─ IPCServer @ ~/.roadies/daemon.sock
        │      └─ subscribe()  ─────────┤
        │                                │
        ├─ RailController (in-process)   │
        │   ├─ subscribe() ──────────────┘   (consomme les events Swift directement)
        │   ├─ access direct au ThumbnailCache (lazy fetch)
        │   ├─ EdgeMonitor (NSEvent global monitor)
        │   └─ N × StageRailPanel (NSPanel, par écran)
        │
        └─ FXLoader (modules SIP-off)

Clients externes :
  CLI roadie ──→ socket Unix ──→ IPCServer
  SketchyBar  ──→ socket Unix ──→ IPCServer (events --follow)
```

## États transitionnels (lifecycle)

### Boot du process unifié (V2)

```text
1. launchd lance ~/Applications/roadied.app/Contents/MacOS/roadied
2. NSApplication.shared.setActivationPolicy(.accessory)
3. DispatchQueue.main.async { Task { @MainActor in
       try await daemon.bootstrap()    // permissions, stages, tiling, observers
       daemon.startRail()              // NOUVEAU : crée RailController, subscribe au bus
   }}
4. NSApp.run()                          // run loop AppKit
5. (asynchrone) RailController crée N panels, démarre EdgeMonitor, fade-in immédiat
   si persistence_ms == 0
```

### Shutdown propre

```text
1. SIGTERM (launchd bootout, ou crash)
2. (existant) Daemon.cleanup() persiste les stages, ferme socket
3. NOUVEAU : RailController.stop() : retire les panels, désinscrit du bus, libère
   les references NSEvent monitor
4. NSApp termine
```

### Crash UI (cas dégradé)

```text
1. Exception SwiftUI dans un renderer (théorique, jamais observé en pratique)
2. Le process roadied entier est tué (perte d'isolation par rapport à V1)
3. launchd détecte exit non-zéro → respawn dans 30 s (ThrottleInterval)
4. Bootstrap complet refait → état restauré depuis disque (stages.toml, etc.)
5. Total downtime utilisateur observable : ≤ 30-35 s
```

## Schémas de données préservés (FR-007/008/016)

Aucun changement aux fichiers persistés ni aux schémas IPC :

- `~/.config/roadies/roadies.toml` — config TOML (lecture seule pour roadie, l'utilisateur édite)
- `~/.local/state/roadies/stages.toml` — état des stages persistés
- `~/.local/state/roadies/daemon.log` — logs JSON-lines
- Schémas JSON socket : commandes (`stage.list`, `stage.switch`, `stage.assign`, `desktop.*`, `window.*`, `display.*`, `daemon.status`, `events.subscribe`, `window.thumbnail`, etc.) et events (`stage_changed`, `desktop_changed`, `window_*`, `display_configuration_changed`, `thumbnail_updated`, etc.) — strictement inchangés.

→ Aucun script tiers, aucun consommateur externe, aucun fichier de configuration n'a besoin d'être modifié par l'utilisateur lors de l'upgrade V1→V2.
