# Implementation Plan: Framework SIP-off opt-in (SPEC-004)

**Branch** : `004-fx-framework` | **Date** : 2026-05-01 | **Spec** : [spec.md](./spec.md)
**Input** : Feature specification from `/specs/004-fx-framework/spec.md`

## Summary

SPEC-004 livre l'infrastructure pour 6 modules SIP-off opt-in (SPEC-005 à SPEC-010). Le daemon `roadied` reste intégralement SIP-on safe et 100 % fonctionnel sans aucun module. Les modules sont des `.dylib` SwiftPM séparés chargés via `dlopen` au boot, avec une lib partagée `RoadieFXCore` (Bézier engine, animation loop CVDisplayLink 60 FPS, OSAX bridge). Une scripting addition `roadied.osax` (bundle Cocoa Objective-C++ minimaliste, ~200 LOC) est injectée dans Dock pour exposer les CGS privés sur fenêtres tierces. Communication daemon ↔ osax via socket Unix locale `/var/tmp/roadied-osax.sock` au protocole JSON-lines. SPEC-004 ne livre AUCUN effet visuel — c'est de l'infrastructure pure validée end-to-end par un module stub. Plafond LOC strict : 800 (cible 600).

## Technical Context

**Language/Version** : Swift 5.9+ (continuation V1) + Objective-C++ pour la scripting addition (`.mm`, ~200 LOC)

**Primary Dependencies** :
- Frameworks système : `Cocoa`, `ApplicationServices`, `CoreGraphics`, `CoreVideo` (CVDisplayLink, nouveau pour AnimationLoop), `IOKit.hid`, `Carbon` (continuation V1)
- Framework privé linké uniquement par l'osax (pas le daemon !) : `/System/Library/PrivateFrameworks/SkyLight.framework` pour les `CGSSetWindow*`. Le daemon n'a que `CGSGetActiveSpace` / `CGSCopyManagedDisplaySpaces` (lecture, déjà présent V1)
- API privées stables (pour daemon, lecture seule, pas de SIP off) : déjà déclarées via `@_silgen_name` en SPEC-002/003
- API privées en écriture (pour osax, SIP off requis) : `CGSSetWindowAlpha`, `CGSSetWindowShadow`, `CGSSetWindowBackgroundBlur`, `CGSSetWindowTransform`, `CGSSetWindowLevel`, `CGSAddWindowsToSpaces`, `CGSSetStickyWindowFlag` — déclarations dans `osax/cgs_private.h`, JAMAIS dans le code daemon
- TOMLKit (déjà présent V1) : parsing `[fx]` config

**Storage** :
- Config : `~/.config/roadies/roadies.toml` extension avec section `[fx]` (déjà partiellement amorcée par SPEC-006 cf out-of-scope SPEC-004 strict, ici juste `[fx] dylib_dir`, `[fx] osax_socket_path`)
- Dylibs : `~/.local/lib/roadie/*.dylib` (path configurable)
- Socket osax : `/var/tmp/roadied-osax.sock` (fixé par convention)
- Bundle osax : `/Library/ScriptingAdditions/roadied.osax/` (path système macOS imposé)
- Logs : `~/.local/state/roadies/daemon.log` (continuation) + nouveaux events `fx_loader.*` et `osax_bridge.*`

**Testing** :
- Tests unitaires XCTest pour `BezierEngine` (table de lookup vs interpolation directe sur points connus), `AnimationLoop` (mock CVDisplayLink), `OSAXBridge` (mock socket), `FXLoader` (mock dlopen)
- Tests d'intégration shell : `tests/integration/11-fx-vanilla.sh` (boot sans modules, vérifie comportement = SPEC-003 strict), `12-fx-loaded.sh` (boot avec stub module + osax, vérifie round-trip noop OK)
- Test "stub module" : un module factice `Tests/RoadieFXStub/` qui sert uniquement à valider le pipeline loader → subscribe → osax send → ack. Il ne fait pas de visuel.

**Target Platform** : macOS 14 (Sonoma) min, 15 (Sequoia) prioritaire, 26 (Tahoe) supporté. Universal x86_64 + arm64. **Daemon SIP-on ; osax requiert SIP partial off pour être chargée par Dock**.

**Project Type** : Single SPM project — continuation des 5 targets V1 + ajout :
- `RoadieFXCore` (target `.dynamicLibrary`)
- `RoadieFXStub` (target `.dynamicLibrary`, dans `Tests/`, utilisé seulement par les tests d'intégration)
- Pas de target SwiftPM pour l'osax (build manuel via `osax/build.sh` car Objective-C++ + bundle, pas de support SPM natif)

**Performance Goals** :
- Boot daemon 0 module : overhead ≤ 10 ms vs SPEC-003 (SC-001)
- Boot daemon 6 modules : tous chargés < 200 ms (SC-002)
- OSAXBridge send round-trip noop : p50 ≤ 20 ms, p95 ≤ 100 ms, p99 ≤ 300 ms (SC-003)
- 0 crash sur 24 h avec activité normale (SC-004)

**Constraints** :
- LOC ajoutées SPEC-004 ≤ **800 strict** (cible 600), cumulés à 4 000 max core SIP-on (constitution G' inchangé)
- Daemon `roadied` final n'a aucun symbole CGS d'écriture linké (SC-007 vérifié via `nm`)
- Pas de root au runtime (sécurité)
- Aucune dépendance runtime nouvelle hors frameworks système (SC-006)
- SIP partial off détecté informativement, NON bloquant pour le chargement

**Scale/Scope** :
- 1 utilisateur, 1 machine, jusqu'à 10 modules chargeables simultanément
- 1 osax injectée dans Dock, 1 socket
- Jusqu'à 1000 commandes OSAX en queue avant drop (vraiment hors normes)

## Constitution Check

*GATE : doit passer avant Phase 0 research. Re-vérifié après Phase 1 design.*

### Constitution Globale (`@~/.speckit/constitution.md`)

| Principe | Conformité |
|---|---|
| **A — Préservation Loi de Conservation** | ✅ aucune intention V1 supprimée, framework est purement additif |
| **B — Documentation continue** | ✅ spec/plan/tasks/research/contracts produits |
| **C — Tests automatisés** | ✅ XCTest unitaires + intégration shell + module stub de validation prévus |
| **D — Sessions traçables (SpecKit)** | ✅ branche `004-fx-framework`, worktree dédié |
| **G — Mode Minimalisme LOC** | ✅ plafond 800 LOC strict, cible 600. Insistance utilisateur **explicite et acceptée** sur la chasse aux lignes inutiles |

### Constitution Projet — AMENDEMENT REQUIS (`.specify/memory/constitution-002.md` → `1.3.0`)

| Principe | Avant | Après (amendement) |
|---|---|---|
| **C'** | « `SLS*`/SkyLight et scripting addition Dock interdits » | « SkyLight lecture seule + scripting addition AUTORISÉS uniquement dans modules opt-in `.dynamicLibrary` séparés. Daemon core jamais lié statiquement à ces APIs. » |
| **G'** (plafond LOC) | core ≤ 4 000 | core ≤ 4 000 (inchangé) + opt-in cumulé ≤ 2 720 plafond strict |

→ L'amendement DOIT être fait dans le commit T010 ci-dessous, avec ADR `docs/decisions/ADR-004-sip-off-modules.md` qui justifie l'écart.

### Vérification cumulée

✅ Toutes les gates passent **après** amendement constitution-002 vers 1.3.0. Sans amendement → STOP.

## Project Structure

### Documentation (this feature)

```text
specs/004-fx-framework/
├── plan.md              # ce fichier
├── spec.md              # spécifications utilisateur
├── research.md          # Phase 0 — décisions techniques (déjà partiellement explorées au /branch)
├── data-model.md        # Phase 1 — entités FXModuleVTable, OSAXCommand, FXRegistry
├── quickstart.md        # Phase 1 — install osax + premier load module stub
├── contracts/
│   ├── fx-module-protocol.md  # ABI C entre daemon et dylib (vtable)
│   └── osax-ipc.md            # protocole JSON-lines daemon ↔ osax
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (généré séparément)
```

### Source Code (repository root)

Continuation V1 + ajouts :

```text
Sources/
├── RoadieCore/
│   ├── FXModule.swift          # NEW — protocol + vtable C
│   ├── EventBus.swift          # EXT — extension public pour subscribe externe (SPEC-003 a déjà l'EventBus interne)
│   └── (V1+V2 inchangés)
├── RoadieFXCore/                # NEW target .dynamicLibrary
│   ├── BezierEngine.swift      # NEW — sample(t) avec lookup table 256
│   ├── AnimationLoop.swift     # NEW — wrapper CVDisplayLink, register/unregister
│   ├── OSAXBridge.swift        # NEW — client socket vers osax, queue + retry
│   └── FXConfig.swift          # NEW — parsing [fx] TOML
├── roadied/
│   ├── main.swift              # EXT — appel `loadFXModulesIfAvailable()` post init
│   ├── FXLoader.swift          # NEW — détecte SIP, dlopen, dlsym, init vtable
│   └── CommandRouter.swift     # EXT — handlers `fx.status`, `fx.reload`
└── roadie/
    └── main.swift              # EXT — verbe `fx` (status, reload)

osax/                            # NEW (hors SPM, build manuel)
├── main.mm                     # Objective-C++ scripting addition entry
├── osax_socket.mm              # serveur socket Unix + dispatch main thread
├── osax_handlers.mm            # 8 commandes (set_alpha, etc.)
├── cgs_private.h               # déclarations CGS d'écriture (privées)
├── Info.plist
└── build.sh                    # compile bundle + sign ad-hoc

scripts/
├── install-fx.sh                # NEW — install osax dans /Library + osascript load
└── uninstall-fx.sh              # NEW — retire osax + dylibs + reload Dock

Tests/
├── RoadieCoreTests/
│   └── FXModuleTests.swift     # NEW — protocol vtable encode/decode
├── RoadieFXCoreTests/           # NEW
│   ├── BezierEngineTests.swift  # samples sur points connus, précision ≥ 0.005
│   ├── AnimationLoopTests.swift # mock CVDisplayLink, register/unregister
│   └── OSAXBridgeTests.swift    # mock socket, queue, retry
├── RoadieFXStub/                # NEW target .dynamicLibrary (test only)
│   └── StubModule.swift         # module factice pour tests d'intégration
└── integration/
    ├── 11-fx-vanilla.sh         # NEW — boot sans modules
    └── 12-fx-loaded.sh          # NEW — boot avec stub + osax

docs/decisions/
└── ADR-004-sip-off-modules.md   # NEW — justifie amendement constitution C'
```

## Phase 0 — Research

Les décisions techniques principales ont été investiguées en amont (cf branche conversationnelle `/branch` du 2026-05-01). Le `research.md` les formalise :

- **Décision 1** : SwiftPM `.dynamicLibrary` + `@_cdecl("module_init")` + `dlopen`/`dlsym` — pattern validé sur macOS, no constraint code signing au-delà de l'identité daemon
- **Décision 2** : ABI C via `FXModuleVTable` (struct C) plutôt que protocole Swift partagé — évite les problèmes de Swift mangling/ABI entre dylibs
- **Décision 3** : `CVDisplayLink` pour AnimationLoop (pas de timer manuel) — la cadence colle au refresh display réel (60 / 120 Hz)
- **Décision 4** : Bézier via lookup table 256 samples + interpolation linéaire — précision ≥ 0.005 suffisante pour 60 FPS, calcul O(1) après init
- **Décision 5** : OSAX bridge socket Unix path fixé `/var/tmp/roadied-osax.sock` — convention yabai-style, mode 0600, UID match
- **Décision 6** : osax bundle Objective-C++ (pas Swift) car Cocoa scripting addition n'est pas compatible Swift de manière documentée — `main.mm` minimaliste sans framework Swift
- **Décision 7** : ADR-004 amendement constitution C' — justifie SIP off **uniquement dans modules opt-in, jamais dans daemon core**

**Output Phase 0** : `research.md` (à rédiger).

## Phase 1 — Design

### Data Model

`data-model.md` (à rédiger). Entités principales :
- `FXModuleVTable` (C struct) : ABI stable entre daemon et dylib
- `FXRegistry` : maintient `[String: FXModule]` keyed par `name`
- `OSAXCommand` (Swift enum) : 8 cas, sérialise en JSON
- `OSAXResult` : `case ok` | `case error(code: String)`
- `BezierCurve` : 4 control points + lookup table 256 samples
- `Animation` (struct) : `wid`, `property`, `from`, `to`, `start`, `duration`, `curve`

### Contracts

`contracts/fx-module-protocol.md` : ABI C de la vtable que chaque module doit exporter
`contracts/osax-ipc.md` : protocole JSON-lines pour les 8 commandes osax

### Quickstart

`quickstart.md` (à rédiger) : installer osax, charger module stub, vérifier round-trip.

### Agent context update

Pas applicable.

## Re-évaluation Constitution Check (post Phase 1 design)

Après Phase 1 design, vérifier :
- ✅ FXLoader < 200 LOC effectives (constitution-002 A')
- ✅ BezierEngine < 100 LOC
- ✅ AnimationLoop < 150 LOC
- ✅ OSAXBridge < 150 LOC
- ✅ osax `.mm` files < 250 LOC cumulés
- ✅ Aucune nouvelle dépendance externe non justifiée (B')
- ✅ Tests unitaires couvrent BezierEngine, AnimationLoop, OSAXBridge avec mocks (H')
- ✅ Module stub vérifie le pipeline end-to-end (sans tests visuels)
- ✅ Daemon final n'a aucun symbole CGS d'écriture (SC-007 obligatoire au check pré-merge)

## Complexity Tracking

**Justification : amendement constitution-002 C' vers 1.3.0**

L'article C' V1 interdisait toute scripting addition. Cet amendement l'autorise uniquement dans modules opt-in séparés, à 6 conditions strictes :

1. Daemon core 100 % fonctionnel sans aucun module chargé (SC-007 + tests SPEC-002/003 régression)
2. Chaque module est `.dynamicLibrary` séparé, jamais lié statiquement
3. Daemon ne crash pas si SIP fully on (no-op gracieux des modules)
4. Scripting addition installée par script utilisateur, JAMAIS automatiquement
5. Chaque module fait l'objet de sa propre SPEC avec audit sécurité
6. Désactivable via flag config par module

→ Justification écrite dans `docs/decisions/ADR-004-sip-off-modules.md`. Le risque sécurité réel est documenté pour l'utilisateur dans `quickstart.md` et `README.md`.

**Pas d'autre violation à justifier.** Le scope reste contenu, le minimalisme respecté, la pureté maintenue.
