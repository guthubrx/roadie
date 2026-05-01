# SPEC-002 — Research : Tiler + Stage Manager

> Résumé exécutif (200 mots)
>
> Cette étude compare yabai (C, macOS Spaces) et AeroSpace (Swift, masquage en coin) pour
> concevoir un window manager « roadies » : tiler modulaire + stage manager opt-in, sans
> désactivation de SIP.
>
> Trois décisions architecturales ressortent clairement des sources :
> (1) adopter le modèle AX par app d'AeroSpace — un thread CFRunLoop par application,
> `AXObserverCreate` + `kAXWindowCreatedNotification` + `kAXFocusedWindowChangedNotification`,
> branché sur un `Task { @MainActor }` — car il ne nécessite aucune API SkyLight ni SIP partiel ;
> (2) implémenter l'arbre de tiling comme un `TreeNode` Swift récursif avec `adaptiveWeight`
> (modèle AeroSpace, supérieur au BSP binaire de yabai pour l'extensibilité Master-Stack) ;
> (3) synchroniser le focus interne via `kAXFocusedWindowChangedNotification` plutôt que par
> polling `leftMouseUp` global, pour corriger le principal défaut d'AeroSpace sur Electron et
> JetBrains.
>
> Le masquage AeroSpace (coin écran) est retenu sur le changement de Space yabai car il
> fonctionne sans SIP, mais nécessite un filtrage explicite de `CGWindowListCopyWindowInfo` pour
> éviter que les fenêtres cachées ne capturent le focus Cmd+Tab.
>
> L'architecture cible : quatre modules Swift (Core, Tiler, StagePlugin, CLI) pour 2 500-3 500 LOC.
> Priorité absolue pour V1 : single-monitor, BSP, CLI Unix socket, config TOML.

---

## 1. Pattern d'event loop AX

### 1.1 yabai — file d'événements maison + AXObserver par process

yabai tourne sur une `pthread` dédiée avec une `sem_t` comme sémaphore. Les événements macOS
arrivent via deux canaux distincts :

**Canal 1 — AXObserver (Accessibility)** : pour chaque application lancée, yabai crée un
`AXObserver` attaché à la `CFRunLoop` du thread principal :

```c
// src/application.c — application_observe()
if (AXObserverCreate(application->pid, application_notification_handler, &application->observer_ref)
        == kAXErrorSuccess) {
    for (int i = 0; i < array_count(ax_application_notification); ++i) {
        AXObserverAddNotification(application->observer_ref,
                                  application->ref,
                                  ax_application_notification[i],
                                  application);
    }
    CFRunLoopAddSource(CFRunLoopGetMain(),
                       AXObserverGetRunLoopSource(application->observer_ref),
                       kCFRunLoopDefaultMode);
}
```

Le callback `application_notification_handler` re-poste vers la file centrale :

```c
// src/application.c — application_notification_handler()
if (CFEqual(notification, kAXCreatedNotification)) {
    event_loop_post(&g_event_loop, WINDOW_CREATED, (void *) CFRetain(element), 0);
} else if (CFEqual(notification, kAXFocusedWindowChangedNotification)) {
    __atomic_store_n(&__pending_window_focus, true, __ATOMIC_RELEASE);
    event_loop_post(&g_event_loop, WINDOW_FOCUSED, (void *)(intptr_t) ax_window_id(element), 0);
} else if (CFEqual(notification, kAXWindowMovedNotification)) {
    event_loop_post(&g_event_loop, WINDOW_MOVED, (void *)(intptr_t) ax_window_id(element), 0);
} else if (CFEqual(notification, kAXUIElementDestroyedNotification)) {
    if (!__sync_bool_compare_and_swap(&window->id_ptr, &window->id, NULL)) return;
    event_loop_post(&g_event_loop, WINDOW_DESTROYED, window, 0);
}
```

**Canal 2 — SkyLight/SLS** : yabai s'abonne également aux notifications `SLSRequestNotificationsForWindows`
(API privée SkyLight) pour les événements d'ordonnancement de fenêtres (`SLS_WINDOW_ORDERED`,
`SLS_WINDOW_DESTROYED`). C'est ici que SIP entre en jeu : ces APIs nécessitent d'être dans le
même contexte que le Dock, ce que la scripting addition (`osax/`) permet.

La file d'événements (`event_loop.h`) est un FIFO protégé par sémaphore :

```c
struct event_loop {
    bool is_running;
    pthread_t thread;
    sem_t *semaphore;
    struct memory_pool pool;
    struct event *head;
    struct event *tail;
};
// Enumération complète des types d'événements gérés :
// APPLICATION_LAUNCHED, WINDOW_CREATED, WINDOW_FOCUSED, WINDOW_MOVED,
// WINDOW_DESTROYED, SLS_WINDOW_ORDERED, SLS_WINDOW_DESTROYED,
// SPACE_CHANGED, DISPLAY_ADDED/REMOVED/MOVED, MOUSE_DOWN/UP ...
```

**Boucle principale** : `CFRunLoop` du thread principal ; la file dédiée (`pthread`) tire les
événements et les dispatch via `dispatch_async` vers le thread principal.

### 1.2 AeroSpace — un thread CFRunLoop par application, MainActor Swift concurrency

AeroSpace n'utilise pas de file d'événements maison. Son architecture repose sur Swift
Concurrency avec `@MainActor` comme sérialiseur global.

**Un thread AX par app** : pour chaque `NSRunningApplication` détectée, AeroSpace crée un
`Thread` Swift dédié qui tourne un `CFRunLoopRun()` et héberge les `AXObserver` de cette app :

```swift
// Sources/AppBundle/tree/MacApp.swift — getOrRegister()
let thread = Thread {
    $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
        let axApp = AXUIElementCreateApplication(nsApp.processIdentifier)
        let handlers: HandlerToNotifKeyMapping = unsafe [
            (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
        ]
        let job = RunLoopJob()
        let subscriptions = (try? unsafe AxSubscription.bulkSubscribe(nsApp, axApp, job, handlers)) ?? []
        let isGood = !subscriptions.isEmpty
        let app = isGood ? MacApp(nsApp, axApp, subscriptions, Thread.current) : nil
        Task { @MainActor in
            allAppsMap[pid] = app
            await wip.signalToAll()
            wipPids[pid] = nil
        }
        if isGood { CFRunLoopRun() }
    }
}
thread.name = "AxAppThread \(nsApp.idForDebug)"
thread.start()
```

La classe `AxSubscription` encapsule l'abonnement AX et le nettoie à la désallocation (`deinit`) :

```swift
// Sources/AppBundle/util/AxSubscription.swift — bulkSubscribe()
guard let obs = unsafe AXObserver.new(nsApp.processIdentifier, handler) else { return [] }
let subscription = AxSubscription(obs: obs, ax: ax)
if try !subscription.subscribe(key) { return [] }
CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
```

**Callback vers MainActor** : le callback `refreshObs` (branché sur `kAXWindowCreatedNotification`
et `kAXFocusedWindowChangedNotification`) programme un `scheduleCancellableCompleteRefreshSession`
sur le MainActor via `Task { @MainActor in }`.

**Observateurs workspace globaux** (`GlobalObserver.swift`) : en plus des AXObserver par app,
AeroSpace s'abonne aux notifications `NSWorkspace` via le center Cocoa, pour les événements
d'application (launch/terminate/activate) et le changement d'espace actif :

```swift
// Sources/AppBundle/GlobalObserver.swift — initObserver()
nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
               queue: .main, using: onNotif)
nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
               queue: .main, using: onNotif)
NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
    Task { @MainActor in
        // Détection click sur desktop d'un autre monitor
        // + détection fermeture de fenêtre par clic sur le bouton close
        scheduleCancellableCompleteRefreshSession(.globalObserverLeftMouseUp)
    }
}
```

### 1.3 Verdict pour notre projet

Adopter l'approche AeroSpace sans réserve :
- Un thread `CFRunLoop` par application, `AXObserver` sur `kAXWindowCreatedNotification` et
  `kAXFocusedWindowChangedNotification` uniquement.
- Callback vers `@MainActor` via `Task { @MainActor in }` (Swift Concurrency).
- `NSWorkspace.shared.notificationCenter` pour launch/terminate/activate.
- Zéro SkyLight, zéro SLS, donc zéro SIP.

La seule amélioration par rapport à AeroSpace : ajouter explicitement
`kAXApplicationActivatedNotification` au niveau app (pas seulement fenêtre) pour synchroniser le
focus immédiatement, sans attendre le prochain `leftMouseUp`.

---

## 2. Modèle de données — arbre de tiling

### 2.1 yabai — BSP binaire strict

yabai représente le layout d'un Space comme un arbre binaire de `window_node` :

```c
// src/view.h — structure noeud BSP
struct window_node {
    struct area area;          // rect calculé pour ce noeud
    struct window_node *parent;
    struct window_node *left;
    struct window_node *right;
    uint32_t window_list[NODE_MAX_WINDOW_COUNT]; // stack de fenêtres
    float ratio;               // 0.1 .. 0.9, rapport gauche/droite
    enum window_node_split split; // SPLIT_Y, SPLIT_X, SPLIT_AUTO
    enum window_node_child child;
};

struct view {
    CFStringRef uuid;
    uint64_t sid;              // Space ID macOS
    struct window_node *root;
    enum view_type layout;     // VIEW_BSP, VIEW_STACK, VIEW_FLOAT
    int top_padding; int bottom_padding; int left_padding; int right_padding;
    int window_gap;
    uint32_t auto_balance;
};
```

Insertion d'une nouvelle fenêtre : le noeud feuille ciblé (insertion_point) est transformé en
noeud intermédiaire, ses deux fils reçoivent l'ancienne fenêtre et la nouvelle. Le calcul de
frame se fait en parcours descendant : à chaque noeud intermédiaire, `area_make_pair` divise
l'aire parent selon `ratio` :

```c
// src/view.c — area_make_pair()
float left_width  = (parent_area->w - gap) * ratio;
float right_width = (parent_area->w - gap) * (1 - ratio);
left_area->w   = (int)left_width;
right_area->w  = (int)right_width;
right_area->x += (int)(left_width + 0.5f) + gap;
```

La décision de split horizontal/vertical est automatique par défaut (`SPLIT_AUTO`) : le noeud
choisit l'axe le plus long (`area.w >= area.h ? SPLIT_Y : SPLIT_X`).

**Forces** : ratio par noeud, balance automatique récursive (`window_node_balance`), léger (C pur).
**Faiblesses** : arbre binaire strict rend Master-Stack complexe à exprimer, pas de notion de
conteneur d'orientation arbitraire, le type de la `view` est un enum global (pas de polymorphisme).

### 2.2 AeroSpace — arbre N-aire orienté, poids adaptatifs

AeroSpace utilise un arbre N-aire où chaque noeud non-feuille est un `TilingContainer` portant
une orientation et un layout :

```swift
// Sources/AppBundle/tree/TilingContainer.swift
final class TilingContainer: TreeNode, NonLeafTreeNodeObject {
    var orientation: Orientation  // .h ou .v
    var layout: Layout            // .tiles ou .accordion
}

// Sources/AppBundle/tree/TreeNode.swift
open class TreeNode {
    private var _children: [TreeNode] = []
    private var adaptiveWeight: CGFloat  // poids relatif dans son parent
    private let _mruChildren: MruStack<TreeNode>  // most-recently-used
    var lastAppliedLayoutPhysicalRect: Rect? = nil
}
```

Le calcul de frame est récursif, propagé dans `layoutRecursive` :

```swift
// Sources/AppBundle/layout/layoutRecursive.swift — layoutTiles()
guard let delta = ((orientation == .h ? width : height)
    - CGFloat(children.sumOfDouble { $0.getWeight(orientation) }))
    .div(children.count) else { return }

for (i, child) in children.enumerated() {
    child.setWeight(orientation, child.getWeight(orientation) + delta)
    let gap = rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0)
    try await child.layoutRecursive(
        i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
        width: orientation == .h ? child.hWeight - gap : width,
        height: orientation == .v ? child.vWeight - gap : height,
        virtual: ...,
        context,
    )
    point = orientation == .h
        ? point.addingXOffset(child.hWeight)
        : point.addingYOffset(child.vWeight)
}
```

Insertion d'une nouvelle fenêtre : la fonction `unbindAndGetBindingDataForNewTilingWindow`
cherche la fenêtre la plus récemment utilisée (`mostRecentWindowRecursive`) et insère la
nouvelle fenêtre juste après dans le même `TilingContainer` parent (même orientation). Si
aucune fenêtre n'existe, elle insère dans `rootTilingContainer`.

**Forces** : N-aire = Master-Stack est exprimable naturellement (un conteneur vertical avec un
enfant à gauche et un conteneur vertical à droite). `adaptiveWeight` distribue l'espace
proportionnellement. `accordion` est un deuxième layout sans changer la structure de l'arbre.
**Faiblesses** : complexité accrue (MRU stack, WEIGHT_AUTO, normalisation des conteneurs opposés).

### 2.3 Comparaison et recommandation

| Critère | yabai BSP binaire | AeroSpace N-aire |
|---|---|---|
| Implémentation BSP | Naturelle | Possible (conteneur 2 enfants) |
| Master-Stack | Difficile | Naturelle |
| Ratios paramétrables | Par noeud | Par poids (adaptiveWeight) |
| Ajout de layouts | Enum global | Protocole (layout par conteneur) |
| Complexité code | Faible (C pur) | Moyenne (Swift classes) |

**Recommandation** : adopter l'approche N-aire d'AeroSpace comme base. Définir un protocole
Swift `Tiler` avec une méthode `layout(rect: CGRect, windows: [WindowID]) -> [WindowID: CGRect]`.
L'implémentation BSP de référence et l'implémentation Master-Stack partagent la même interface.
L'arbre de nœuds Swift est gardé en mémoire ; le calcul de frame est un parcours récursif
synchrone (pas async — seule l'application des frames via AX est async).

---

## 3. Stratégie de masquage par workspace

### 3.1 yabai — Spaces macOS natifs

yabai mappe chaque workspace sur un Space macOS. Changer de workspace = appeler
`scripting_addition_focus_space(sid)` qui invoque une API SkyLight privée pour commuter le
Space actif. Les fenêtres restent physiquement sur leur Space, invisibles naturellement.

**Avantages** : le masquage est géré par le Compositor macOS, performances parfaites, pas
d'artefact visuel.
**Inconvénients** : nécessite SIP partiellement désactivé (`csrutil enable --without fs --without debug`)
pour charger la scripting addition dans Dock.app. L'API SkyLight `scripting_addition_focus_space`
est privée et cassable à chaque mise à jour macOS.

### 3.2 AeroSpace — masquage en coin d'écran

AeroSpace déplace les fenêtres des workspaces non actifs dans un coin de l'écran (hors zone
visible), en mémorisant leur position relative :

```swift
// Sources/AppBundle/tree/MacWindow.swift — hideInCorner()
func hideInCorner(_ corner: OptimalHideCorner) async throws {
    guard let nodeMonitor else { return }
    if !isHiddenInCorner {
        guard let windowRect = try await getAxRect() else { return }
        let topLeftCorner = windowRect.topLeftCorner
        let monitorRect = windowRect.center.monitorApproximation.rect
        prevUnhiddenProportionalPositionInsideWorkspaceRect =
            CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
    }
    // Déplacement vers bottomLeftCorner ou bottomRightCorner selon les monitors adjacents
    let p = nodeMonitor.visibleRect.bottomRightCorner - onePixelOffset
    setAxFrame(p, nil)
}
```

Le choix du coin est calculé pour minimiser les conflits avec les monitors adjacents
(`monitorToOptimalHideCorner` dans `refresh.swift`).

**Avantages** : zéro SIP, zéro API privée pour le masquage, fonctionne sur tout macOS depuis
Ventura.
**Inconvénients** :
- Les fenêtres cachées restent dans la liste Cmd+Tab si l'application est active, ce qui peut
  générer des focus indésirables.
- L'animation de déplacement vers le coin peut être visible sur certaines apps (Zoom gère ce cas
  avec un offset spécial dans le code AeroSpace).
- Les fenêtres au niveau `popup` ou `dialog` échappent parfois au masquage.

### 3.3 Notre choix

Adopter l'approche AeroSpace (coin d'écran) pour V1. Mitigation du problème Cmd+Tab : à chaque
déplacement vers le coin, appeler `window.setNativeMinimized(true)` pour les fenêtres d'apps
non actives — cela les retire du Cmd+Tab tout en permettant de les restaurer via
`setNativeMinimized(false)` lors du switch de workspace. Alternative plus légère : filtrer les
fenêtres hors-écran dans notre propre liste de fenêtres mais laisser macOS gérer Cmd+Tab (à
tester empiriquement).

Pour V2, évaluer l'approche via `CGSSetWindowWorkspace` (API privée CGS, disponible sans SIP
si l'app est signée avec la bonne entitlement `com.apple.developer.spaces`).

---

## 4. Click-to-focus : pourquoi AeroSpace est fragile et comment faire mieux

### 4.1 L'architecture du focus dans AeroSpace

AeroSpace ne maintient pas de focus "click-to-focus" en temps réel. Son état de focus interne
(`_focus: FrozenFocus`) est mis à jour uniquement lors d'une `refreshSession`, déclenchée par un
événement. Le chemin principal pour synchroniser le focus natif vers l'état interne est :

```swift
// Sources/AppBundle/focusCache.swift — updateFocusCache()
func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer { return }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()  // met à jour _focus
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
}
```

`updateFocusCache` est appelé depuis `runHeavyCompleteRefreshSession` qui est lui-même déclenché
par `scheduleCancellableCompleteRefreshSession`. Le problème : cette chaîne n'est déclenchée que
sur des événements spécifiques (app activate, `leftMouseUp` global, `kAXWindowCreatedNotification`,
`kAXFocusedWindowChangedNotification`).

### 4.2 Le problème avec Electron et JetBrains

Les applications Electron (VS Code, Slack, Discord) et JetBrains (IntelliJ, Rider) ont une
architecture multi-process ou multi-view qui génère des séquences d'événements AX non standard :

- Sur un click dans VS Code, le système envoie `kAXFocusedWindowChangedNotification` à
  l'application *après* un délai non déterministe, ou parfois sur le sous-process renderer
  plutôt que sur le process principal.
- JetBrains crée des fenêtres "popup" (completion, tooltips) qui déclenchent
  `kAXFocusedWindowChangedNotification` avant la vraie fenêtre principale.

Conséquence : AeroSpace peut avoir un état interne où la fenêtre A est "focusée" alors que le
système a effectivement donné le focus à la fenêtre B. Le `refreshObs` callback est enregistré
uniquement sur `kAXWindowCreatedNotification` et `kAXFocusedWindowChangedNotification` au niveau
de l'AXUIElement application — pas au niveau de chaque fenêtre individuelle.

La recherche dans les issues GitHub confirme l'absence d'issue spécifique "click focus Electron"
par ce nom exact, mais l'issue #12 (focus follow mouse, ouverte par l'auteur lui-même) révèle
que le "focus follow mouse" n'est volontairement pas implémenté. Le `leftMouseUp` global dans
`GlobalObserver` est l'unique mécanisme pour récupérer le focus après un click, et il est
labellisé `// todo reduce number of refreshSession in the callback`.

### 4.3 Comment yabai gère le focus

yabai est plus passif : il écoute `kAXFocusedWindowChangedNotification` via son observer AX par
app, et met à jour `wm->focused_window_id` dans `window_did_receive_focus`. La gestion des
fenêtres en stack est explicite :

```c
// src/event_loop.c — window_did_receive_focus()
wm->focused_window_id = window->id;
wm->focused_window_psn = window->application->psn;
struct view *view = window_manager_find_managed_window(&g_window_manager, window);
if (!view) return;
struct window_node *node = view_find_window_node(view, window->id);
// Réordonnancement dans la stack du noeud
memmove(node->window_order + 1, node->window_order, sizeof(uint32_t) * i);
node->window_order[0] = window->id;
```

yabai ne cherche pas à "corriger" le focus — il enregistre ce que macOS lui dit. Les raccourcis
(`yabai -m window --focus`) appellent directement `AXUIElementPerformAction(kAXRaiseAction)` +
`NSRunningApplication.activate`.

### 4.4 Solution pour notre projet

Enregistrer un `AXObserver` supplémentaire sur `kAXApplicationActivatedNotification` au niveau
de chaque app (en plus de `kAXFocusedWindowChangedNotification`). Lorsque cet observer est
déclenché, appeler immédiatement `app.getFocusedWindow()` (interrogation de `kAXFocusedWindowAttr`
sur l'AXUIElement) et synchroniser `_focus` sans attendre le `refreshSession` complet.

Ce mécanisme garantit que même si Electron ou JetBrains retarde leur
`kAXFocusedWindowChangedNotification`, le changement d'app active déclenche la synchronisation.

En cas d'app qui ne coopère pas du tout (rare) : le `leftMouseUp` global reste le filet de
sécurité existant dans AeroSpace.

---

## 5. API privées utilisées

### 5.1 yabai — scripting addition + SkyLight

La scripting addition (`osax/loader.m`) injecte un bundle dans `Dock.app` via
`task_for_pid` + `mach_vm_write` + `thread_create_running`. C'est ce qui permet d'accéder aux
fonctions SkyLight (`SLS*`) :

```c
// src/osax/loader.m — injection dans Dock.app
pid_t pid = get_dock_pid();
if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS) { return 1; }
mach_vm_write(task, code, (vm_address_t) shell_code, sizeof(shell_code));
vm_protect(task, code, sizeof(shell_code), 0, VM_PROT_EXECUTE | VM_PROT_READ);
thread_create_running(task, thread_flavor, ...);
```

Cela nécessite que `task_for_pid` fonctionne sur Dock.app, ce qui implique SIP partiellement
désactivé. Une fois injecté, le payload expose les fonctions `sa.h` :
`scripting_addition_focus_space`, `scripting_addition_move_window_to_space`,
`scripting_addition_set_layer`, etc.

### 5.2 AeroSpace — une seule API privée

Le dossier `Sources/PrivateApi/` ne contient qu'une seule déclaration de fonction privée :

```c
// Sources/PrivateApi/include/private.h
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);
```

Cette fonction permet d'extraire le `CGWindowID` d'un `AXUIElement` directement, sans passer
par `CGWindowListCopyWindowInfo`. C'est l'équivalent du `@_silgen_name("_AXUIElementGetWindow")`
qu'on utilise déjà dans `stage.swift` du projet. Elle ne nécessite pas SIP désactivé — elle est
simplement non documentée.

AeroSpace utilise également `NSEvent.addGlobalMonitorForEvents` (API publique mais qui nécessite
l'entitlement Accessibility) et l'activation via `NSRunningApplication.activate` (public).

### 5.3 Inventaire pour notre projet — zéro SIP

Fonctions utilisables sans SIP :

| Fonction | Type | Usage |
|---|---|---|
| `_AXUIElementGetWindow` | Privée non-SIP | Extraire CGWindowID depuis AXUIElement |
| `AXObserverCreate` / `AXObserverAddNotification` | Publique AX | Abonnement events fenêtre |
| `NSEvent.addGlobalMonitorForEvents(.leftMouseUp)` | Publique Cocoa | Détection click global |
| `NSWorkspace.shared.notificationCenter` | Publique | Launch/terminate/activate app |
| `NSRunningApplication.activate(options:)` | Publique | Donner le focus natif |
| `AXUIElementPerformAction(kAXRaiseAction)` | Publique AX | Remonter une fenêtre |
| `CGWindowListCopyWindowInfo` | Publique CG | Liste fenêtres visibles |
| `NSScreen.screens` | Publique | Détection monitors |

Fonctions à éviter (nécessitent SIP off ou injection) :
- `SLSRequestNotificationsForWindows` (SkyLight, SIP)
- `SLSOrderWindow` (SkyLight, SIP)
- `scripting_addition_*` (yabai osax, SIP)
- `task_for_pid` sur process tiers (SIP)

---

## 6. Multi-monitor

### 6.1 yabai — display ID + spaces par display

yabai identifie les displays via `CGDisplayRegisterReconfigurationCallback` branché sur sa file
d'événements :

```c
// src/display.c — display_handler()
static DISPLAY_EVENT_HANDLER(display_handler) {
    if (flags & kCGDisplayAddFlag)
        event_loop_post(&g_event_loop, DISPLAY_ADDED, (void *)(intptr_t) did, 0);
    else if (flags & kCGDisplayRemoveFlag)
        event_loop_post(&g_event_loop, DISPLAY_REMOVED, (void *)(intptr_t) did, 0);
    else if (flags & kCGDisplayMovedFlag)
        event_loop_post(&g_event_loop, DISPLAY_MOVED, (void *)(intptr_t) did, 0);
}
```

Chaque display a ses propres Spaces (via `display_space_list`), et chaque Space a sa propre
`struct view`. Le workspace est pinné à un display via l'API Spaces : il n'y a pas de workspace
"flottant" non attaché à un display.

### 6.2 AeroSpace — monitors par NSScreen, workspaces flottants

AeroSpace identifie les monitors via `NSScreen.screens`, indexés par position dans la liste
AppKit. L'astuce clé : les workspaces sont identifiés par leur position d'écran
(`screenPoint`), pas par un ID de display. Cela permet de "migrer" un workspace vers un autre
monitor si la configuration physique change :

```swift
// Sources/AppBundle/tree/Workspace.swift — rearrangeWorkspacesOnMonitors()
for (oldScreen, _) in screenPointToVisibleWorkspace {
    guard let newScreen = newScreens.minBy({ ($0 - oldScreen).vectorLength }) else { continue }
    newScreenToOldScreenMapping[newScreen] = oldScreen  // migration par distance minimale
}
```

Un workspace invisible a un `assignedMonitorPoint` qui pointe vers son dernier monitor connu.
`forceAssignedMonitor` permet de "pinner" un workspace à un monitor spécifique (config TOML).

**Cas monitor principal vs secondaire** : AeroSpace traite tous les monitors symétriquement.
`mainMonitor` est le monitor dont le frame AppKit a son origine à (0,0) — il n'a pas de
sémantique spéciale dans le tiling.

### 6.3 Recommandation pour notre projet

**V1 : single-monitor strict.** Ne gérer qu'un seul `Monitor` objet dans Core. Refuser
silencieusement de tiler sur des monitors secondaires.

**V2 : multi-monitor.** Adopter le modèle AeroSpace : `[CGPoint: Workspace]` (position
d'écran comme clé), `forceAssignedMonitor` optionnel en config, migration par distance minimale
lors du changement de configuration. Éviter l'API `CGDisplayRegisterReconfigurationCallback`
directement : utiliser `NSWorkspace.shared.notificationCenter` avec
`NSApplicationDidChangeScreenParametersNotification` (API publique).

---

## 7. Configuration et CLI

### 7.1 yabai — `.yabairc` + socket UNIX

yabai se configure via un script shell exécuté au démarrage (`~/.config/yabai/yabairc`), qui
appelle `yabai -m ...`. Le binaire client communique avec le daemon via un socket UNIX
(`/tmp/yabai_$UID.socket`). Le protocole est du texte brut (chaîne de commande).

**Forces** : simple, scriptable en bash, rechargement à chaud facile.
**Faiblesses** : aucun typage, erreurs silencieuses si la syntaxe est mauvaise, l'ordre
d'exécution des commandes dans le script dépend du shell.

### 7.2 AeroSpace — TOML + socket UNIX + NWConnection

AeroSpace utilise le format TOML (`~/.config/aerospace/aerospace.toml`), parsé via
`TOMLDecoder` (bibliothèque Swift externe). La communication CLI-daemon passe par
`NWConnection` (Network framework) sur un socket UNIX, avec un protocole JSON :

```swift
// Sources/Common/model/clientServer.swift
// Sources/AppBundle/server.swift
// Le client envoie une commande JSON, le serveur répond JSON
```

**Forces** : TOML est lisible, typé, rechargeable à chaud. La bibliothèque `TOMLDecoder`
gère le parsing. Le protocole JSON est auto-documenté.
**Faiblesses** : dépendance externe (`TOMLDecoder`, `HotKey`, `OrderedCollections`) — la liste
des `import` dans `parseConfig.swift` révèle 4 packages tiers.

### 7.3 Recommandation pour notre projet

Adopter TOML pour la configuration. Pour le parser : utiliser `TOMLDecoder` si les dépendances
sont acceptées, sinon un sous-ensemble minimal à la main (les besoins sont simples : sections,
tableaux de strings, booléens, entiers). Ne pas réimplémenter de zéro sauf si le projet adopte
une philosophie "zéro dépendance" explicite.

Pour la CLI : socket UNIX + protocole ligne-par-ligne (commande en texte, réponse en texte ou
JSON). Le format JSON est préférable pour les commandes qui retournent des données structurées
(`list-windows`, `list-workspaces`). Les commandes d'action (`focus left`, `move to workspace 2`)
peuvent rester textuelles pour la compatibilité shell.

---

## 8. Synthèse architecturale pour notre projet

### 8.1 Principes directeurs

- Tiler et StageManager sont **séparés** : le Tiler ne sait pas que le StageManager existe.
- Le Core est le seul module qui parle au système (AX, NSWorkspace).
- La CLI est un client léger sans logique propre.
- Zéro SIP requis, zéro injection de code.

### 8.2 Architecture en couches

```
┌─────────────────────────────────────────────────┐
│  CLI (binaire séparé)                           │
│  ~ 200 LOC : encode commande → socket, affiche  │
└──────────────────┬──────────────────────────────┘
                   │ socket UNIX (texte / JSON)
┌──────────────────▼──────────────────────────────┐
│  Core (daemon — @MainActor)                     │
│  ~ 600 LOC                                      │
│  • AXEventLoop : thread/app, AXObserver,        │
│    CFRunLoop, callback → MainActor              │
│  • GlobalObserver : NSWorkspace notifs          │
│  • WindowRegistry : [WindowID: WindowState]     │
│  • DisplayManager : monitors, workspaces        │
│  • Server : NWListener socket UNIX              │
└───┬────────────────┬────────────────────────────┘
    │ events         │ events
┌───▼──────────┐  ┌─▼─────────────────────────────┐
│  Tiler       │  │  StagePlugin (opt-in)          │
│  ~ 900 LOC   │  │  ~ 400 LOC                    │
│  protocol    │  │  • Observe Core events        │
│  Tiler       │  │  • Gère groupes de fenêtres   │
│  impl BSP    │  │  • Masque/montre via AX frame │
│  impl Master │  │  • N'a pas accès au Tiler     │
│  Stack       │  └───────────────────────────────┘
└──────────────┘
```

### 8.3 Module Core

Fichiers Swift estimés :

| Fichier | Responsabilité | LOC estimées |
|---|---|---|
| `Core/AXEventLoop.swift` | Thread par app, AXObserver, CFRunLoop | 120 |
| `Core/GlobalObserver.swift` | NSWorkspace, leftMouseUp global | 80 |
| `Core/WindowRegistry.swift` | Dictionnaire WindowID → WindowState | 100 |
| `Core/FocusManager.swift` | État focus interne, synchronisation | 80 |
| `Core/DisplayManager.swift` | NSScreen, workspaces, mapping | 100 |
| `Core/Server.swift` | NWListener, dispatch commandes | 120 |
| `Core/Config.swift` | Parsing TOML, structures de config | 100 |
| **Total Core** | | **~700** |

### 8.4 Module Tiler

```swift
// Protocole central
protocol Tiler {
    func layout(rect: CGRect, windows: [WindowID]) -> [WindowID: CGRect]
    func insertWindow(_ id: WindowID, after: WindowID?) -> Void
    func removeWindow(_ id: WindowID) -> Void
    func moveWindow(_ id: WindowID, direction: CardinalDirection) -> Void
    func resizeWindow(_ id: WindowID, direction: CardinalDirection, delta: CGFloat) -> Void
}
```

| Fichier | Responsabilité | LOC estimées |
|---|---|---|
| `Tiler/TilerProtocol.swift` | Protocole + types communs | 60 |
| `Tiler/TreeNode.swift` | Classe de base noeud N-aire | 150 |
| `Tiler/TilingContainer.swift` | Noeud intermédiaire avec orientation | 100 |
| `Tiler/BSPTiler.swift` | Implémentation BSP binaire | 200 |
| `Tiler/MasterStackTiler.swift` | Implémentation Master-Stack | 180 |
| `Tiler/LayoutEngine.swift` | Calcul récursif des frames | 150 |
| `Tiler/WorkspaceState.swift` | Arbre + état par workspace | 100 |
| **Total Tiler** | | **~940** |

### 8.5 Module StagePlugin

| Fichier | Responsabilité | LOC estimées |
|---|---|---|
| `Stage/StageManager.swift` | Groupes de fenêtres, état actif | 120 |
| `Stage/WindowGroup.swift` | Groupe de fenêtres (ex : projet) | 80 |
| `Stage/HideStrategy.swift` | Stratégie de masquage (coin, minimize) | 100 |
| `Stage/StageObserver.swift` | Abonnement aux events Core | 100 |
| **Total Stage** | | **~400** |

### 8.6 Module CLI

| Fichier | Responsabilité | LOC estimées |
|---|---|---|
| `CLI/main.swift` | Point d'entrée, parse args | 60 |
| `CLI/SocketClient.swift` | NWConnection vers daemon | 80 |
| `CLI/OutputFormatter.swift` | Affichage texte / JSON | 60 |
| **Total CLI** | | **~200** |

**Total V1 estimé : ~2 240 LOC** (dans la fourchette cible 2 000-4 000).

### 8.7 Flux d'un événement typique : nouvelle fenêtre

```
AXObserver(kAXWindowCreatedNotification)
  → thread AX app
    → Task { @MainActor in }
      → AXEventLoop.onWindowCreated(windowId, appPid)
        → WindowRegistry.register(window)
          → Tiler.insertWindow(windowId, after: focusedWindowId)
            → LayoutEngine.recalculate(workspace)
              → [windowId: CGRect] → Core.applyFrames()
                → MacWindow.setAxFrame() sur thread AX app
          → StagePlugin.onWindowAdded(window) [si actif]
```

---

## 9. Pièges identifiés et anti-patterns

### 9.1 Erreurs de yabai à éviter

**SIP comme prérequis** : la dépendance à la scripting addition crée une barrière à l'entrée
forte. Toute mise à jour macOS peut casser l'injection dans Dock.app (l'auteur a dû adapter
le code pour Sequoia et Tahoe — voir les `workspace_is_macos_sequoia()` dans `event_loop.c`).

**SLS notifications fragiles** : yabai utilise `SLSRequestNotificationsForWindows` pour les
événements d'ordre. Cette API n'est pas documentée et son comportement a changé entre Sonoma et
Sequoia (le code contient des branches conditionnelles nombreuses sur la version d'OS).

**Arbre BSP binaire** : rend l'implémentation Master-Stack artificielle (il faut simuler un
conteneur N-aire avec un BSP binaire).

**Absence de typage fort** : les événements sont des entiers (`enum event_type`) passés avec
`void *context`. Les erreurs de cast sont silencieuses en C.

### 9.2 Erreurs d'AeroSpace à éviter

**Click-to-focus non synchrone** : le `leftMouseUp` global comme seul mécanisme de
re-synchronisation du focus est trop tardif pour les apps Electron/JetBrains. Solution décrite
en §4.4.

**Race conditions au démarrage** : `MacApp.getOrRegister` utilise un système de `wipPids`
(Work In Progress) avec un `AwaitableOneTimeBroadcastLatch` pour éviter les doubles
enregistrements. Ce pattern est correct mais complexe. Adopter une approche plus simple :
sérialiser toutes les opérations d'enregistrement sur le `@MainActor` et utiliser un simple
dictionnaire `inProgressPids: Set<pid_t>`.

**Dépendances externes** : `TOMLDecoder`, `HotKey`, `OrderedCollections`. Pour un projet
suckless, considérer un parser TOML maison (< 200 lignes pour un sous-ensemble).

**`todo` dans le code de production** : le code AeroSpace contient de nombreux `// todo` sur
des chemins critiques (le commentaire sur `normalizeContainers`, la note sur `MRU propogation`,
etc.). Documenter les compromis acceptés plutôt que de laisser des `todo` sans issue associée.

### 9.3 Pièges communs aux deux outils

**Fenêtres au démarrage (race condition)** : les deux outils ont des mécanismes complexes pour
gérer les apps déjà lancées au démarrage du WM. AeroSpace vérifie `isStartup` pour décider
vers quel workspace placer les fenêtres. yabai a un `add_lost_front_switched_event`. Stratégie
recommandée : au démarrage, snapshotter l'état actuel (toutes les fenêtres via
`CGWindowListCopyWindowInfo`) puis traiter chaque fenêtre comme si elle venait d'être créée,
dans l'ordre de leur `kCGWindowLayer`.

**Gestion des popups / dialogs** : AeroSpace a un système de `MacosPopupWindowsContainer`
pour les fenêtres non-standard. yabai les exclut via `window_manager_should_manage_window`. Ces
fenêtres (completion JetBrains, menus contextuels, overlays Electron) doivent être identifiées
et exclues du tiling dès la réception de l'événement `kAXWindowCreatedNotification`, via
`kAXSubroleAttr` (valeur `AXDialog`, `AXSheet`, `AXPopupButton`).

**Fenêtres minimisées et plein écran natif** : les deux outils ont des états spéciaux pour ces
cas. Stratégie recommandée : maintenir un `layoutReason: LayoutReason` enum par fenêtre
(`.standard`, `.minimized`, `.nativeFullscreen`) et ne pas appliquer le tiling aux fenêtres
hors `.standard`.

**Problème Zoom** : AeroSpace contient un commentaire explicite sur un bug Zoom avec les offsets
d'un pixel. Les apps de conférence vidéo ont des comportements AX non standard. Prévoir une
liste de `knownBundleIds` avec des workarounds spécifiques (comme `KnownBundleId.swift` dans
AeroSpace).

---

## 10. Plan de lecture pour l'utilisateur

### Fichiers yabai (C)

| Fichier | Résumé |
|---|---|
| `src/event_loop.h` / `event_loop.c` | Définition de la file d'événements (FIFO pthread) et tous les handlers d'événements système. C'est le cœur du daemon. |
| `src/application.c` | Comment yabai s'abonne aux notifications AX par application. La fonction `application_notification_handler` est le point d'entrée de tous les événements fenêtre. |
| `src/view.h` / `view.c` | Structure de données BSP : `struct window_node` (noeud binaire), `struct view` (workspace), calcul récursif des frames via `area_make_pair`. |
| `src/window_manager.c` | Orchestrateur : gère le dictionnaire de fenêtres, décide si une fenêtre doit être tilée, applique les frames via AX. |
| `src/sa.h` / `osax/loader.m` | L'interface de la scripting addition et le code d'injection dans Dock.app. Révèle pourquoi SIP est nécessaire. |
| `src/display.c` | Enregistrement du callback de reconfiguration display. Simple et instructif. |
| `src/space_manager.c` | Gestion des Spaces macOS. Toutes les opérations passent par les fonctions `scripting_addition_*`. |

### Fichiers AeroSpace (Swift)

| Fichier | Résumé |
|---|---|
| `Sources/AppBundle/tree/MacApp.swift` | Création du thread AX par application, abonnement AX, pattern `wipPids`. Le modèle de concurrence central. |
| `Sources/AppBundle/util/AxSubscription.swift` | Encapsulation RAII d'un AXObserver. Simple et réutilisable directement. |
| `Sources/AppBundle/GlobalObserver.swift` | Abonnements NSWorkspace et `leftMouseUp` global. Montre comment mixer Cocoa notifications et Swift Concurrency. |
| `Sources/AppBundle/layout/refresh.swift` | La `refreshSession` : sequence complète de synchronisation (focus, model, layout). La "transaction" principale du daemon. |
| `Sources/AppBundle/layout/layoutRecursive.swift` | Calcul récursif des frames pour `tiles` et `accordion`. Directement adaptable pour BSP et Master-Stack. |
| `Sources/AppBundle/tree/TreeNode.swift` | Classe de base de l'arbre N-aire avec `adaptiveWeight`, `MruStack`, `bind`/`unbind`. |
| `Sources/AppBundle/tree/TilingContainer.swift` | Noeud intermédiaire avec orientation et layout. |
| `Sources/AppBundle/tree/Workspace.swift` | Workspace comme racine de l'arbre, mapping monitor ↔ workspace, garbage collection. |
| `Sources/AppBundle/tree/MacWindow.swift` | `hideInCorner` / `unhideFromCorner` (masquage), `nativeFocus`, `garbageCollect`. |
| `Sources/AppBundle/focus.swift` | Modèle de focus (`LiveFocus`, `FrozenFocus`), `setFocus`, callbacks `onFocusChanged`. |
| `Sources/AppBundle/focusCache.swift` | `updateFocusCache` : synchronisation état interne ← macOS. |
| `Sources/AppBundle/model/Monitor.swift` | Abstraction monitor via `NSScreen`, normalisation des coordonnées (top-left vs bottom-left). |
| `Sources/PrivateApi/include/private.h` | La seule API privée utilisée : `_AXUIElementGetWindow`. |
| `Sources/AppBundle/config/parseConfig.swift` | Parsing TOML avec `TOMLDecoder`. Montre les dépendances externes acceptées. |
| `Sources/AppBundle/subscriptions.swift` | Système d'abonnement aux events serveur (pour le mode `--subscribe` de la CLI). |
