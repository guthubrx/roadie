# FX Module Protocol — ABI C entre daemon et `.dylib`

**Date** : 2026-05-01

Spécification de l'ABI C utilisée par le daemon `roadied` pour charger et appeler les modules FX. Cette ABI est **stable** et garantie par contrat — un module compilé contre la version N continue à fonctionner avec un daemon version N+x tant que cette interface n'évolue pas.

---

## Header partagé

Le daemon et chaque module incluent (Swift via `@_cdecl`, ou C via header explicite) :

```c
// fx_module.h — partagé daemon ↔ modules

#ifndef FX_MODULE_H
#define FX_MODULE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FXModuleVTable {
    const char* name;
    const char* version;
    void (*subscribe)(void* event_bus);   // event_bus = pointeur opaque, cast via FXEventBus_*
    void (*shutdown)(void);
} FXModuleVTable;

#ifdef __cplusplus
}
#endif

#endif
```

---

## Convention d'export par module

Chaque module DOIT exporter une fonction unique :

```swift
// dans Sources/RoadieXxx/Module.swift

import RoadieFXCore

@_cdecl("module_init")
public func module_init() -> UnsafeMutablePointer<FXModuleVTable> {
    let vtable = UnsafeMutablePointer<FXModuleVTable>.allocate(capacity: 1)
    vtable.pointee.name = strdup("xxx")
    vtable.pointee.version = strdup("0.1.0")
    vtable.pointee.subscribe = { busPtr in
        let bus = FXEventBus.from(opaquePtr: busPtr)
        XxxModule.shared.subscribe(to: bus)
    }
    vtable.pointee.shutdown = {
        XxxModule.shared.shutdown()
    }
    return vtable
}
```

**Notes** :
- `strdup` pour les strings : la mémoire est ownée par le module, libérée seulement au unload (acceptable, ~50 octets par module)
- Les closures C `subscribe` / `shutdown` ne capturent rien (`{ busPtr in ... }` sans `[self]`) — le contexte vient du singleton module
- `FXEventBus.from(opaquePtr:)` est un helper de `RoadieFXCore` qui cast le pointeur opaque en `EventBus` Swift

---

## Side daemon — chargement

```swift
// Sources/roadied/FXLoader.swift

import RoadieCore

public final class FXLoader {
    public func loadAll(from dir: URL) -> [FXModule] {
        let dylibs = try? FileManager.default.contentsOfDirectory(at: dir, ...)
            .filter { $0.pathExtension == "dylib" }

        return dylibs?.compactMap { url in
            guard let handle = dlopen(url.path, RTLD_LAZY) else {
                logger.error("dlopen failed", path: url.path, dlerror: String(cString: dlerror()))
                return nil
            }
            guard let initSym = dlsym(handle, "module_init") else {
                logger.error("module_init symbol missing", path: url.path)
                dlclose(handle)
                return nil
            }
            typealias InitFn = @convention(c) () -> UnsafeMutablePointer<FXModuleVTable>
            let initFn = unsafeBitCast(initSym, to: InitFn.self)
            let vtablePtr = initFn()
            return FXModule(
                vtable: vtablePtr.pointee,
                dylibHandle: handle,
                path: url,
                loadedAt: Date()
            )
        } ?? []
    }
}
```

---

## Side daemon — appel `subscribe`

```swift
let bus = EventBus.shared           // EventBus singleton du daemon
let busOpaque = Unmanaged.passUnretained(bus).toOpaque()
module.vtable.subscribe(busOpaque)  // appelle la fn dans le dylib
```

---

## Side daemon — appel `shutdown`

```swift
public func unloadAll() {
    for module in registry.allModules {
        module.vtable.shutdown()    // ferme observers, queues, sockets
        dlclose(module.dylibHandle) // libère le dylib
    }
    registry.clear()
}
```

Appelé sur :
- Signal `SIGTERM` reçu par le daemon
- `roadied --quit` clean
- `roadie fx reload` (avant de recharger)

---

## Garanties de stabilité ABI

- La struct `FXModuleVTable` ne sera **pas réorganisée** entre versions mineures du daemon
- Si une nouvelle méthode est ajoutée à la vtable (ex: `pause()` / `resume()`), elle sera **ajoutée à la fin** de la struct, jamais insérée au milieu
- Les modules anciens fonctionneront toujours (les nouvelles méthodes seront détectées par `nullptr` check côté daemon)
- Versioning : si breaking change ABI, on renomme `module_init` → `module_init_v2` et le daemon teste les deux

---

## Garanties de pureté code

- Le daemon **JAMAIS** ne link statiquement un module
- Le daemon **JAMAIS** ne charge plus de `RTLD_LAZY` (pas de `RTLD_NOW` qui force tout chargement)
- Le daemon catch toute exception lors du `module_init()` (try/catch C++ via wrap C)
- Si un module crash dans `subscribe()` ou `shutdown()`, le crash NE doit PAS prendre le daemon avec lui (signal handler à investiguer en SPEC-005 si nécessaire)

---

## Tests de validation contrat

Côté unitaire :
- `FXLoaderTests` : mock filesystem avec dylibs valides + invalides, vérifier le filtrage
- `FXLoaderTests` : module sans `module_init` → loaded == nil
- `FXLoaderTests` : module avec vtable invalide (nom vide) → rejet + log

Côté intégration :
- `tests/integration/12-fx-loaded.sh` : load le `RoadieFXStub` (module factice), vérifier que `subscribe` est appelé et qu'un event passe end-to-end
