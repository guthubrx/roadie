# Research — Framework SIP-off opt-in (SPEC-004)

**Date** : 2026-05-01
**Status** : Final

Recherche technique sur l'architecture de modules opt-in chargeables dynamiquement avec scripting addition Dock pour CGS privés. Validations issues d'une investigation Explore agent + sources externes (yabai, Apple docs, Swift forums).

---

## Décision 1 — `.dynamicLibrary` SwiftPM + `dlopen` + `@_cdecl`

**Décision** : utiliser `SwiftPM .library(name: "RoadieFXCore", type: .dynamic, targets: ["RoadieFXCore"])` pour produire des `.dylib` chargeables à runtime via `dlopen`. Chaque module exporte une fonction `@_cdecl("module_init")` qui retourne un `UnsafeMutablePointer<FXModuleVTable>` (struct C ABI).

**Rationale** :
- Supporté nativement sur macOS sans hack. Validé via Swift Forums + plusieurs projets prod.
- `@_cdecl` évite le mangling Swift, permet `dlsym` direct.
- Vtable C plutôt que protocole Swift partagé : évite les problèmes d'ABI Swift entre dylibs (Swift n'a pas d'ABI stable garantie cross-dylib pour les protocoles non-`@objc`).
- Code signing : ad-hoc OK pour usage personnel. Si distribution future, mêmes Developer ID requis sur daemon et dylibs.

**Alternatives considérées** :
- **Bundle `.framework`** : trop lourd, utilise des paths Apple-specific.
- **Plugins SPM `Package.swift` plugin API** : compile-time only, pas runtime.
- **Statique avec flag de compilation** : viole la compartimentation (modules linkés au daemon).

---

## Décision 2 — ABI C via vtable (pas protocole Swift)

**Décision** : interface `FXModuleVTable` = struct C avec 4 pointeurs de fonction :

```c
typedef struct {
    const char* name;
    const char* version;
    void (*subscribe)(void* event_bus_ptr);
    void (*shutdown)(void);
} FXModuleVTable;
```

Chaque module dylib alloue cette struct au `module_init`, retourne le pointeur. Le daemon copie la struct dans son `FXRegistry`.

**Rationale** :
- ABI C stable, indépendante de Swift version
- 4 pointeurs = minimum suffisant
- `event_bus_ptr` : pointeur opaque, le module doit caster via une fonction helper dans `RoadieFXCore` (qui connaît le vrai type)

**Alternatives considérées** :
- **Protocole Swift `@objc`** : force NSObject, lourd
- **Protocole Swift natif partagé via target** : ABI Swift instable cross-dylib

---

## Décision 3 — Bézier engine via lookup table 256 samples

**Décision** : `BezierEngine.sample(t: Double) -> Double` calcule à l'init une table de 256 samples [t → y] via la formule Bézier 4 points (Newton's method ou bisection sur paramètre x). Au runtime : `sample(t)` = lookup index `Int(t * 255)` + interpolation linéaire avec sample suivant.

**Rationale** :
- Précision ≥ 0.005 sur [0, 1] vérifiée vs calcul direct
- O(1) au runtime, pas d'allocation, friendly cache
- 60 FPS sur 20 fenêtres en parallèle = 1200 samples/sec, négligeable
- Init en O(256 * iterations Newton) ≤ 5 ms par courbe (acceptable au boot)

**Alternatives considérées** :
- **Calcul direct à chaque tick** : O(iterations Newton) à chaque tick, ~10 ms par fenêtre par tick → trop coûteux
- **Lookup 1024 samples** : précision plus haute mais 4× mémoire pour gain non perceptible visuellement

**Référence** : implémentation similaire à WebKit `UnitBezier.h` et CSS animation engines.

---

## Décision 4 — `CVDisplayLink` pour AnimationLoop

**Décision** : `AnimationLoop` utilise `CVDisplayLinkCreateWithActiveCGDisplays` pour synchroniser sur la cadence display réelle. Callback exécuté dans son propre thread, dispatch async sur main pour les opérations Cocoa.

**Rationale** :
- Cadence native (60 / 120 Hz selon ProMotion), pas de jitter
- Pas de timer Foundation manuel à entretenir
- Thread dédié = pas de blocage main
- Standard Apple (utilisé par toutes les apps à animations natives)

**Alternatives considérées** :
- **`Timer.scheduledTimer(withTimeInterval: 1/60)`** : drift, jitter, pas de sync display
- **`DispatchSourceTimer`** : plus précis que Timer mais toujours pas display-synced
- **`CADisplayLink`** : iOS only, pas macOS

---

## Décision 5 — Socket Unix path fixé `/var/tmp/roadied-osax.sock`

**Décision** : `OSAXBridge` se connecte à `/var/tmp/roadied-osax.sock`. Mode socket : `0600` (owner-only). UID match vérifié côté osax (refus si UID ≠ daemon owner).

**Rationale** :
- `/var/tmp/` = world-writable + sticky bit, OK pour socket utilisateur
- Path fixé en dur (pas configurable) : 1 utilisateur 1 socket, pas besoin de complexité
- Convention yabai-style : `/tmp/yabai_<USER>.socket`

**Alternatives considérées** :
- **`~/.roadies/osax.sock`** : `~` n'est pas accessible depuis Dock injecté (process Dock = root daemon, pas user)
- **TCP localhost** : surdimensionné, ouvre port, surface attaque
- **XPC** : XPC service requiert App Sandbox, incompatible avec scripting addition non-sandbox

---

## Décision 6 — Bundle osax en Objective-C++ (`.mm`)

**Décision** : `roadied.osax/Contents/MacOS/roadied` = binaire Objective-C++ compilé via `clang++ -bundle -framework Cocoa -framework SkyLight`. Pas de Swift dans l'osax.

**Rationale** :
- Scripting addition charge dans Dock = **process non-Swift**. Charger la swift runtime dynamique dans Dock = risque crash + bloat.
- Objective-C++ = compilable directement par `clang++`, ABI C, runtime Cocoa minimal.
- yabai utilise ce pattern depuis 10 ans (`sa.dylib` est en C/C++).
- 200 LOC `.mm` = très lisible, peu de surface bugs.

**Alternatives considérées** :
- **Swift osax** : faisable techniquement mais plus risqué (Swift runtime dans Dock)
- **Pure C** : OK mais Cocoa NSXPC / dispatch easier en Objective-C

---

## Décision 7 — Amendement constitution-002 C' vers 1.3.0

**Décision** : amender l'article C' qui interdit les scripting additions. La nouvelle version autorise `SLS`/scripting addition uniquement dans modules opt-in séparés, à 6 conditions strictes (cf plan.md Complexity Tracking).

**Rationale** :
- L'utilisateur a explicitement demandé cette voie B (cf message du 2026-05-01) après revue des alternatives
- L'amendement reste **étroit** : daemon core inchangé, 6 conditions de garde, ADR-004 trace la justification
- Sans amendement, SPEC-005 à SPEC-010 sont impossibles → pas de famille SIP-off du tout

**ADR** : `docs/decisions/ADR-004-sip-off-modules.md` à créer en T010 du `tasks.md`.

**Conditions de garde explicites** :
1. Daemon core 100 % fonctionnel sans aucun module chargé (SC-007 + tests SPEC-002/003 régression)
2. Chaque module est `.dynamicLibrary` séparé, jamais lié statiquement
3. Daemon ne crash pas si SIP fully on (no-op gracieux des modules)
4. Scripting addition installée par script utilisateur, jamais automatiquement
5. Chaque module fait l'objet de sa propre SPEC avec audit sécurité
6. Désactivable via flag config par module

---

## Décision 8 — `csrutil status` non bloquant

**Décision** : le daemon log l'état SIP au boot (informatif) mais ne bloque pas le `dlopen` des modules même si SIP est fully on. Logique : si SIP est on, l'osax ne sera pas chargée par Dock → `OSAXBridge` ne pourra pas se connecter → modules logent warning et font no-op. Pas besoin d'un check supplémentaire dans le daemon, l'échec est gracieux par construction.

**Rationale** :
- Évite une dépendance dure entre détection SIP et chargement modules
- Permet à l'utilisateur de bouger SIP entre sessions sans devoir tout réinstaller
- Cohérent avec la philosophie "fail loud + no fallback" : si osax pas joignable → log warning explicite, pas un échec silencieux

---

## Sources externes consultées

- [Building and loading dynamic libraries at runtime in Swift — theswiftdev.com](https://theswiftdev.com/building-and-loading-dynamic-libraries-at-runtime-in-swift/)
- [yabai Wiki — Disabling SIP](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection)
- [yabai source — sa.dylib injection pattern](https://github.com/koekeishiya/yabai/tree/master/sa)
- [Apple TSP — Scripting Additions documentation (legacy)](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/conceptual/ASLR_terminology.html)
- [WebKit UnitBezier.h — référence Bézier lookup table](https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/UnitBezier.h)
- [SkyLightWindow — exemples CGS privés](https://github.com/Lakr233/SkyLightWindow)
- [Eclectic Light — controlling SIP via csrutil](https://eclecticlight.co/2024/08/21/controlling-system-integrity-protection-using-csrutil-a-reference/)

---

## Risques résiduels & mitigations

| Risque | Probabilité | Mitigation |
|---|---|---|
| Apple casse le pattern scripting addition macOS .X+1 | Faible (10 ans de stabilité, 2 instabilités majeures sur ce délai) | Monitor yabai upstream, attendre 1-4 semaines après update macOS avant de patcher soi-même |
| Swift ABI cross-dylib pète à une release Swift | Très faible (vtable C neutralise) | Régression unit-test sur load module stub, audit pré-release |
| osax crash dans Dock | Faible (200 LOC très lisibles, try/catch sur CGS calls) | Dock auto-restart par macOS, daemon retry connexion |
| Module malicieux distribué ailleurs | Moyenne | Checksum FR-025 + doc utilisateur "as-is" + signature ad-hoc forcée |
| Sécurité réelle réduite par SIP off | Réelle | Doc utilisateur explicite, machine dev de l'utilisateur déjà SIP off (acceptation informée) |
