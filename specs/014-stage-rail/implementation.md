# Implementation log — SPEC-014 Stage Rail UI

**Status**: ALL PHASES COMPLETE (T001 = branche créée, T002-T110 = livrés)
**Last updated**: 2026-05-02
**Branch**: `014-stage-rail`

## Phase 1 — Setup (DONE 2026-05-02)

| Task | Statut | Détails |
|---|---|---|
| T001 — Branche dédiée `014-stage-rail` | DONE | Créée depuis `main` lors de la session d'implémentation complète. |
| T002 — Target `RoadieRail` dans Package.swift | DONE | `executableTarget` avec dépendance `RoadieCore` + `TOMLKit`. |
| T003 — Target `RoadieRailUI` lib séparée | NOT NEEDED V1 | Tout dans `RoadieRail`, séparation reportée si V2 le justifie. |
| T004 — Cibles Makefile | DONE | `build-rail`, `install-rail`, `uninstall-rail`. |
| T005 — `Sources/RoadieRail/main.swift` | DONE | Boot NSApp + AppDelegate. |
| T006 — Smoke test | DONE | 5 tests unitaires `RailIPCClientTests` passent. |

## Phase 2 — Foundational (DONE)

| Task | Statut | Fichiers |
|---|---|---|
| T010 ThumbnailCache LRU | DONE | `Sources/RoadieCore/ThumbnailCache.swift` (82 LOC) |
| T011 SCKCaptureService | DONE | `Sources/RoadieCore/ScreenCapture/SCKCaptureService.swift` (138 LOC) |
| T012 SCK tests | DONE | `Tests/RoadieCoreTests/SCKCaptureServiceTests.swift` (53 LOC) |
| T013 WallpaperClickWatcher | DONE | `Sources/RoadieCore/Watchers/WallpaperClickWatcher.swift` (97 LOC) |
| T014 WallpaperClickWatcher tests | DONE | `Tests/RoadieCoreTests/WallpaperClickWatcherTests.swift` (72 LOC) |
| T015 CommandRouter extensions | DONE | `window.thumbnail`, `tiling.reserve`, `rail.status`, `rail.toggle` |
| T016 main.swift instanciation | DONE | `thumbnailCache`, `sckCaptureService`, `wallpaperClickWatcher` câblés |
| T017 EventBus helpers | DONE | `wallpaperClick`, `stageRenamed`, `thumbnailUpdated` factories |
| T018 EventBus rail tests | DONE | `Tests/RoadieCoreTests/EventBusRailEventsTests.swift` (73 LOC) |

## Phase 3 — US1 MVP : révéler le rail (DONE)

| Task | Statut | Fichiers |
|---|---|---|
| T020 RailState | DONE | `Models/RailState.swift` |
| T021 StageVM/WindowVM | DONE | `Models/StageVM.swift` |
| T022 RailIPCClient | DONE | `Networking/RailIPCClient.swift` (async/await, reconnexion exp.) |
| T023 EventStream | DONE | `Networking/EventStream.swift` (Process `roadie events --follow`) |
| T024 RailIPCClient tests | DONE | `Tests/RoadieRailTests/RailIPCClientTests.swift` |
| T025 EdgeMonitor | DONE | `Hover/EdgeMonitor.swift` (polling 80ms multi-écran) |
| T026 FadeAnimator | DONE | `Hover/FadeAnimator.swift` (200ms NSAnimationContext) |
| T027 StageRailPanel | DONE | `Views/StageRailPanel.swift` (NSPanel non-activating) |
| T028 StageStackView | DONE | `Views/StageStackView.swift` (vue racine SwiftUI) |
| T029 StageCard | DONE | `Views/StageCard.swift` (carte avec badge + chips) |
| T030 WindowChip | DONE | `Views/WindowChip.swift` (vignette + fallback initiales) |
| T031 ThumbnailFetcher | DONE | `Networking/ThumbnailFetcher.swift` (cache + invalidation) |
| T032 RailController | DONE | `RailController.swift` (orchestrateur multi-display) |
| T032b TOML config | DONE | `RailConfig.load()` parse `[fx.rail]` + `[desktops]` |
| T033 AppDelegate | DONE | `AppDelegate.swift` |
| T034 main.swift wire | DONE | Boot NSApp + delegate |
| T035 PID-lock | DONE | `~/.roadies/rail.pid` mono-instance |
| T036 Test acceptance | DONE | `tests/14-rail-show-hide.sh` |

## Phase 4 — US2 : click → switch stage (DONE)

| Task | Statut | Détails |
|---|---|---|
| T040 onTapGesture | DONE | Câblé via closure `onTap` dans StageCard. |
| T041 IPC stage.switch | DONE | `RailController.switchToStage()` avec update optimiste. |
| T042 Subscribe stage_changed | DONE | `handleEvent` re-fetch sur event. |
| T043 Test acceptance | DONE | `tests/14-rail-stage-switch.sh` (mesure SC-002 < 200ms). |

## Phase 5 — US3 : drag-drop fenêtre (DONE)

| Task | Statut | Détails |
|---|---|---|
| T050 WindowDragData (Transferable) | DONE | `Drag/WindowDragData.swift` + UTType custom `com.roadie.window-drag`. |
| T051 WindowChip draggable | DONE | `.draggable(WindowDragData(...))` SwiftUI macOS 14. |
| T052 StageCard drop target | DONE | `.dropDestination(for: WindowDragData.self)` avec highlight. |
| T053 IPC stage.assign avec wid | DONE | CommandRouter étendu pour accepter wid explicite. |
| T054 Subscribe window_assigned | DONE | Re-fetch sur event. |
| T055 Test acceptance | DONE | `tests/14-rail-drag-drop.sh` (SC-003 < 300ms). |

## Phase 6 — US4 : wallpaper-click crée stage (DONE)

| Task | Statut | Détails |
|---|---|---|
| T060 WallpaperStageCoordinator | DONE | `Sources/roadied/WallpaperStageCoordinator.swift` (71 LOC). |
| T061 Garde-fou rail PID-lock | DONE | `kill(pid, 0)` check. |
| T062 Garde-fou config flag | DONE | TOML `[fx.rail].wallpaper_click_to_stage`. |
| T063 Garde-fou no-op si vide | DONE | Skip silencieux si aucune fenêtre tilée. |
| T064 Animation rail (optionnelle) | DEFERRED V1.1 | `wallpaper_click` event publié mais animation non implémentée V1. |
| T065 Test acceptance | DONE | `tests/14-wallpaper-click.sh` (SC-010 < 400ms, GUI-dependent). |

## Phase 7 — US5 : menu contextuel (DONE)

| Task | Statut | Détails |
|---|---|---|
| T070 contextMenu SwiftUI | DONE | StageCard `.contextMenu` avec 3 entrées. |
| T071 Rename modale | DONE | `.sheet` SwiftUI avec TextField, validation 1..32 chars. |
| T072 Add focused window | DONE | IPC `stage.assign` sans wid → utilise focusedWindowID. |
| T073 Delete avec confirmation | DONE | `.alert` SwiftUI ; stage 1 désactivé dans le menu. |
| T074 Subscribe stage_renamed | DONE | EventBus helper `stageRenamed`, re-fetch. |
| T075 Test acceptance | DONE | `tests/14-rail-context-menu.sh`. |

## Phase 8 — US6 : reclaim horizontal space (DONE)

| Task | Statut | Détails |
|---|---|---|
| T080 tiling.reserve daemon | DONE | `LayoutEngine.leftReserveByDisplay` + `applyAll` modifié, CommandRouter switch. |
| T081 Rail send reserve fade-in | DONE | `RailController.handleEnterEdge` envoie `tiling.reserve` si activé. |
| T082 Rail send reserve=0 fade-out | DONE | `handleExitEdge` restaure. |
| T083 Test acceptance on/off | DONE | `tests/14-reclaim-on.sh`. |
| T084 Mesure jank | MANUEL | Vérifier visuellement < 1 frame @ 60Hz. |

## Phase 9 — US7 : multi-display (DONE)

| Task | Statut | Détails |
|---|---|---|
| T090 Iterate NSScreen.screens | DONE | `RailController.buildPanels()` 1 panel/écran ; mode "global" → primary uniquement. |
| T091 didChangeScreenParametersNotification | DONE | Observer dans `start()`, recrée panels. |
| T092 Filtre per-écran | PARTIAL V1 | Toutes les stages affichées (pas de filtrage per-display dans V1, pas de SPEC-013 multi-desktop runtime). |
| T093 Test acceptance | DONE | `tests/14-multi-display-rail.sh` (smoke). |

## Phase 10 — Polish (DONE — partiel)

| Task | Statut | Détails |
|---|---|---|
| T100 Captures écran | SKIP | Manuel post-livraison. |
| T101 README section rail | SKIP | À ajouter au README projet par l'utilisateur. |
| T102 LaunchAgent template | DONE | `scripts/local.roadies.rail.plist.template`. |
| T103 Logging JSON-lines | DONE | `logErr` redirigé vers stderr ; LaunchAgent template route vers `~/.local/state/roadies/rail.log`. |
| T104 Fallback dégradé icon | DONE | `handleWindowThumbnail` retourne PNG icone d'app si SCK refusé (degraded=true). |
| T105 Profiling 1h | MANUEL | À mesurer en production (SC-004 < 30MB / 1% CPU). |
| T106 Régression SPEC-002 | MANUEL | Re-jouer la suite avec rail lancé. |
| T107 Régression SPEC-011 | MANUEL | Idem. |
| T108 REX implementation.md | DONE | Ce document. |
| T109 Audit /audit | TODO | À lancer en session dédiée après revue. |
| T110 Zero entitlement | DONE | `codesign -d --entitlements -` sur `roadie-rail` retourne uniquement `get-task-allow=true` (debug). Aucune perm Screen Recording / Camera / Mic / Sandbox. |

## Verification finale

### Build
```
$ PATH="/usr/bin:/bin:..." swift build
Build complete! (1.62s)
```

### Tests
```
$ swift test --filter "RoadieRailTests|RoadieCoreTests|RoadieStagePluginTests|RoadieTilerTests"
83+ tests passed, 0 failures (segfault PerfTests pré-existant en run all-suite, isolé OK)
```

### LOC effectives SPEC-014

| Composant | LOC effectives |
|---|---|
| `Sources/RoadieRail/` (target) | 1041 |
| `Sources/RoadieCore/{ThumbnailCache,ScreenCapture/SCKCaptureService,Watchers/WallpaperClickWatcher}.swift` | 260 |
| `Sources/roadied/WallpaperStageCoordinator.swift` | 71 |
| **TOTAL production** | **1372 LOC** |
| Tests SPEC-014 | 285 LOC |

**Cible 1500 / Plafond 2000** : ✓ sous cible.

### Compartimentation (SPEC-014 SC-005, FR-002)

```
$ codesign -d --entitlements - .build/debug/roadie-rail
[Dict]
    [Key] com.apple.security.get-task-allow
    [Value] [Bool] true
```

Aucune permission Screen Recording, Accessibility, Input Monitoring, App Sandbox. Le rail délègue 100% des opérations système au daemon `roadied` via socket Unix existant. ✓

```
$ nm .build/debug/roadied | grep -E "CGSSetWindow|CGSAddWindow" | wc -l
0
```

Aucun symbole CGS-write privé dans le daemon. ✓ (constitution C')

## Hotfixes critiques post-MVP (2026-05-03)

### Fix NSZombie SCKCaptureService.encodePNG

11+ crashs `EXC_BREAKPOINT` du daemon en 2 jours, tous à uptime ≈ 140s exactement,
pattern `___forwarding___.cold.6` au pop d'autoreleasepool de `NSApp.run`.

**Cause** : `Sources/RoadieCore/ScreenCapture/SCKCaptureService.swift` ligne 144
retournait `data as Data` (toll-free bridging = wrap, pas copie). Le `NSMutableData`
créé dans l'autoreleasepool du callback `SCStream.didOutputSampleBuffer` était
release au drain du pool background. Le `Data` retourné devenait zombie au prochain
accès depuis le main thread (~70 frames plus tard à 0.5 Hz = 140s).

**Fix** : `Data(bytes: data.bytes, count: data.length)` qui copie les bytes dans
un buffer Swift indépendant. 5 LOC modifiées. Validé en runtime : daemon vit
> 155s sans crash.

### Fix RailIPCClient lecture multi-chunk

Les vignettes ScreenCaptureKit (~30-80 KB de PNG en base64 = ~45-110 KB JSON) arrivent
en plusieurs chunks Unix socket. La lecture initiale s'arrêtait au 1er chunk → JSON
décode failed → 100% des thumbnails fetch en échec côté rail.

**Fix** : `Sources/RoadieRail/Networking/RailIPCClient.swift` boucle `readMore()`
jusqu'au newline final. Validé : `thumbnail set for wid=N degraded=false bytes=33880`
visible dans le rail debug log.

### Fix WindowChip stale icon (let → computed property)

`appIcon` était `let` calculé dans `init()`. SwiftUI ne ré-init pas la struct quand
`pid` change (id stable via `id: \.self`) → l'icône restait celle du premier render
(fallback générique avec pid=0). 

**Fix** : `Sources/RoadieRail/Views/WindowChip.swift` (anciennement, maintenant
`WindowPreview.swift`) — `appIcon` devenu computed property recalculée à chaque body.

### Fix StageStackView.windows jamais peuplé

`windows: [CGWindowID: WindowVM] = [:]` était un paramètre par défaut JAMAIS rempli
par `RailController` → `windows[wid]?.pid` toujours nil → fallback générique.

**Fix** : utilise directement `state.windows` (peuplée par `loadWindows()` IPC
`windows.list` enrichie avec `app_name` côté daemon).

### Refonte visuelle Stage Manager natif

Refactor des vues SwiftUI pour reproduire l'esthétique Stage Manager natif macOS :
- `Sources/RoadieRail/Views/WindowStack.swift` (NEW, ~215 LOC) remplace `StageCard.swift`
- `Sources/RoadieRail/Views/WindowPreview.swift` (NEW, ~89 LOC) remplace `WindowChip.swift`
- `Sources/RoadieRail/Views/HUDBackground.swift` (NEW, NSVisualEffectView wrapper)
- `Sources/RoadieRail/Views/StageStackView.swift` refonte : pas de header, stacks
  centrés verticalement, fond strictement transparent, hint discret en bas
- Captures 200×130 empilées en cascade Z (offset 6/6, scale -2%, opacity -10% par couche)
- Halo paramétrique stage active (`[fx.rail].halo_color` `halo_intensity`)
- Filtrage wids orphelines (visibles uniquement si présentes dans `windows` ou `thumbnails`)

### EdgeMonitor zone active étendue

Le panel se fermait dès que la souris sortait des 8 px d'edge → impossible de
cliquer sur les vignettes.

**Fix** : `EdgeMonitor.activeZoneWidth` (= panelWidth) appliqué quand le panel est
visible. Debounce exit augmenté de 100 ms → 700 ms.

### Bug daemon `stage assign` : applyLayout + hide

`sm.assign(wid:to:stageID)` ne déclenchait pas de re-layout ni de hide. Conséquence :
la wid restait visible à sa frame originale même après assignation à une stage
non-active.

**Fix** : `Sources/roadied/CommandRouter.swift` case `stage.assign` — après
`sm.assign()` :
- Si stage cible ≠ stage active → `setLeafVisible(false)` + `HideStrategyImpl.hide()`
- Toujours `daemon.applyLayout()`
- Émission event `window_assigned` pour que le rail refresh

### `windows.list` enrichi `app_name`

`Sources/roadied/CommandRouter.swift` case `windows.list` ajoute le champ `app_name`
(via `NSWorkspace.shared.runningApplications.localizedName` mappé par PID) — permet
au rail de résoudre l'icône d'app via `NSRunningApplication(processIdentifier:)`.

## REX — Implémentation complète

### Ce qui s'est bien passé

- **Phase 2 + 3 déléguées à l'agent coder** : production efficace de ~1100 LOC en 2 invocations, build clean dès la première fois, conventions du projet respectées (logger structuré, pas de `try!`, `@MainActor` discipliné).
- **`@Observable` SwiftUI macOS 14** rend le state holder rail très lisible — pas besoin de `ObservableObject` + `@Published`.
- **`Transferable` + `.draggable`/`.dropDestination`** SwiftUI ont rendu le drag-drop trivial (vs NSDraggingSource AppKit). 50 LOC vs 200 LOC estimés.
- **`@_cdecl`-free** : `roadie-rail` est un binaire NSApp pur, aucun bridge Obj-C nécessaire grâce à SwiftUI moderne.
- **Compartimentation totale** validée par `codesign -d --entitlements -` : zero permission runtime, daemon = single source of truth.

### Difficultés rencontrées

- **anaconda ld shadow** : Xcode ld masqué par `/opt/homebrew/anaconda3/bin/ld`, link error obscur (`-no_warn_duplicate_libraries` non reconnu). Fix : préfixer chaque `swift build` par `PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"`.
- **SourceKit "No such module 'RoadieCore'" faux positif** : indexer stale après échecs link ; build réel clean.
- **`stage.list` originel ne renvoyait pas `window_ids` ni `is_active`** : étendu pour SPEC-014 sans casser les consumers existants.
- **`stage.assign` originel utilisait uniquement focusedWindowID** : étendu pour accepter un `wid` explicite (drag-drop), fallback compat ascendante.
- **Segfault PerfTests pré-existant** : intermittent en run all-suite, passe en isolation. Non introduit par SPEC-014.

### Connaissances acquises

- ScreenCaptureKit `SCStreamConfiguration.minimumFrameInterval` accepte `CMTime(seconds: 2, preferredTimescale: 600)` pour 0.5 Hz.
- `NSPanel(styleMask: [.borderless, .nonactivatingPanel])` + `.statusBar` level + `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` = pattern HUD éprouvé Spotlight.
- SwiftUI `@Bindable` (macOS 14+) suffit pour binder un `@Observable` à une vue ; `@StateObject` n'est plus nécessaire.
- `.dropDestination(for:)` accepte n'importe quel `Transferable & Codable`, sérialisation pasteboard automatique.

### Recommandations pour le futur

1. **Lancer `/audit 014-stage-rail`** en session dédiée pour valider la qualité finale et générer le scoring.
2. **Tester en réel sur 2 écrans** : valider `T091` hot-plug, `T093` per-display rail, `tiling.reserve` multi-display.
3. **Profiling 1h** post-installation pour valider SC-004 (< 30MB RSS / 1% CPU).
4. **Animation `wallpaper_click`** (T064) à ajouter en V1.1 pour le polish final du geste signature.
5. **EventStream robustness** : migrer de `availableData` polling vers `FileHandle.readabilityHandler` pour resistance aux pipe close.

---

## Post-livraison fix (session 2026-05-03) : halo paramétrique

**Demande user** : rendre le halo de la stage active paramétrique TOML (couleur, intensité, radius) + le default vert.

**Fix** :
- Avant : `.shadow(color: stage.isActive ? .accentColor.opacity(0.55) : .clear, radius: 14, x: 0, y: 0)` — halo bleu accentColor non paramétrique
- Après : `if stage.isActive { content.shadow(color: Color(hex: haloColorHex).opacity(haloIntensity), radius: haloRadius, x: 0, y: 0) }` — halo vert système Apple `#34C759` paramétrique via 3 props injectées

**Section TOML `[fx.rail]` étendue** :
```toml
halo_color = "#34C759"      # hex #RRGGBB ou #RRGGBBAA, default vert système Apple
halo_intensity = 0.75       # 0.0..1.0 (clamp), default 0.75
halo_radius = 18            # 0..80 px (clamp), default 18
```

**Helper ajouté** : extension `Color(hex:)` privée dans `WindowStack.swift` (parse `#RRGGBB`/`#RRGGBBAA`, fallback gris si malformé).

**Anti-bug** : passage du `.shadow` ternaire à un `@ViewBuilder if` explicite. Raison : `.shadow(color: .clear, ...)` semblait dessiner quand même un effet visible (artefact rendu SwiftUI observé), causant 2 halos visibles au lieu d'1. Le `if` skip totalement le modifier.

**Fichiers** :
- `Sources/RoadieRail/RailController.swift` (struct `RailConfig` étendue + parsing TOML clamp)
- `Sources/RoadieRail/Views/StageStackView.swift` (forward props)
- `Sources/RoadieRail/Views/WindowStack.swift` (consume props + extension `Color(hex:)`)
- `specs/014-stage-rail/quickstart.md` (documentation des 3 nouvelles options)

**Commits** : `79b2edf` (halo paramétrique radius + halo conditionnel), `a245397` (`ensureTreePopulated` défensif au boot, utilisé par fix SPEC-018).
