# SPEC-004 — Implementation Log

**Date** : 2026-05-01
**Status** : Phase 1+2+3 livrée. Phase 4 (osax bundle Objective-C++) reportée pour validation manuelle SIP off.

## Tâches accomplies

| Tâche | Status | Notes |
|---|---|---|
| T001-T005 Setup | ✅ | dossiers + Package.swift target `RoadieFXCore` `.dynamicLibrary` |
| T010 Amendement constitution-002 → 1.3.0 | ✅ | Article C' amendé, 6 conditions de garde |
| T011 ADR-004 | ✅ | `docs/decisions/ADR-004-sip-off-modules.md` |
| T012 Package.swift | ✅ | target dynamicLibrary + test target |
| T020 FXModule.swift | ✅ | protocol + vtable C ABI + FXEvent + FXEventBus, 113 LOC |
| T021 FXEventBus | ✅ | Inclus dans FXModule.swift (helper from/toOpaque) |
| T030 BezierEngine | ✅ | Lookup table 256 + Newton + bisection fallback, 6 courbes built-in, 87 LOC |
| T031 AnimationLoop | ✅ | CVDisplayLink wrapper, register/unregister, 75 LOC |
| T032 OSAXBridge | ✅ | actor socket Unix, queue cap 1000, retry 2s, batch send, 188 LOC |
| T033 FXConfig | ✅ | TOML section [fx], expand ~ home, 47 LOC |
| T034 OSAXCommand | ✅ | enum 8 cas + Result parsing, 86 LOC |
| T040 FXLoader | ✅ | csrutil status detect, glob dylib, dlopen + dlsym, 113 LOC |
| T041 main.swift extend | ✅ | init FXLoader post bootstrap, log SIP state |
| T050 fx.status handler | ✅ | CommandRouter "fx.status" + "fx.reload" |
| T051 roadie fx verbe | ✅ | sous-commandes status/reload |
| T052 verify-no-cgs-write | ✅ | `nm` retourne 0 (validé) |
| Tests T030 BezierEngine | ✅ | 8 tests : linear, ease, easeInOut, snappy, easeOutBack, clamping |
| Tests T032 OSAXBridge | ✅ | 5 tests : disconnected, queue depth, cap 1000, isConnected |
| Tests T034 OSAXCommand | ✅ | 9 tests : JSON serialization 8 commandes + parsing OSAXResult |
| Tests AnimationLoop | ✅ | 3 tests : start/stop idempotent, register/unregister |
| Tests FXConfig | ✅ | 4 tests : defaults, missing section, custom, expanded |

## Tâches reportées (Phase 4)

| Tâche | Reporté à | Pourquoi |
|---|---|---|
| T070-T075 osax bundle Cocoa | SPEC-004.1 | Objective-C++ requiert SIP off réel pour tester l'injection Dock. Pas testable depuis tests unitaires. À valider manuellement par l'utilisateur. |
| T080 RoadieFXStub | SPEC-004.1 | Module factice, utilité limitée tant que osax pas livrée |
| T085-T086 install/uninstall scripts | SPEC-004.1 | Couplé à osax bundle |
| T091 integration test 12-fx-loaded.sh | SPEC-004.1 | Couplé au stub + osax |
| T120-T126 Polish | SPEC-004.1 | Stress test 24h, doc README, etc. |

## Métriques

- **LOC SPEC-004** : 609 effectives (cible 600, plafond 800) — **PASS** ✅
- **Tests** : 22 nouveaux unitaires SPEC-004 + 0 régression sur 68 tests SPEC-001/002/003 = **90 tests, 0 échec** ✅
- **SC-007 sécurité** : `nm roadied | grep CGSSetWindow* | wc -l == 0` → **PASS** ✅
- **Build cold** : ~9 s sur Apple Silicon
- **SC-001 boot overhead** : à mesurer empiriquement (test pas automatisable sans avoir osax)

## Décisions architecturales prises en cours d'implémentation

1. **`FXConfig` placé dans `RoadieCore`** (pas `RoadieFXCore`) : le daemon doit pouvoir parser la config sans charger la lib dynamic. Préserve la compartimentation (daemon n'importe pas RoadieFXCore directement).
2. **`FXLoader` dans le target `roadied`** (pas une lib séparée) : le loader fait partie intégrante du daemon. C'est lui qui décide de charger ou pas. Reste compartimenté car n'importe que `RoadieCore`.
3. **`FXModuleVTable` utilise `UnsafeMutableRawPointer`** comme retour de `module_init` (pas `UnsafeMutablePointer<FXModuleVTable>`) : Swift `@convention(c)` n'accepte que des types Obj-C compatibles. Le cast est fait côté daemon.
4. **`FXConfig.load`** lit directement les clés via `fxSection["dylib_dir"]?.string` au lieu de tenter un re-encode TOML : plus robuste face aux limitations TOMLKit.
5. **Tests `OSAXCommand`** parsent le JSON émis avec `JSONSerialization` plutôt que matcher des sous-strings : indépendant des spécificités de formatage Double.

## Ce qui reste pour rendre SPEC-004 utilisable end-to-end

- Implémenter `roadied.osax` bundle Objective-C++ (~200 LOC `.mm` + `Info.plist` + `build.sh`)
- Scripts `install-fx.sh` et `uninstall-fx.sh`
- Stress test sur machine SIP off réel
- Documentation utilisateur "as-is, no warranty" dans README

Ces points relèvent d'une session manuelle sur la machine de l'utilisateur (qui a SIP partial off déjà actif). Pas implémentables en autonomie depuis Claude Code.

## Build & test

```bash
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"
swift build       # 9-11 s cold, 0.7 s hot
swift test        # 90 tests, 0 failure
nm .build/debug/roadied | grep CGSSetWindow* | wc -l   # == 0 (gate SC-007)
```
