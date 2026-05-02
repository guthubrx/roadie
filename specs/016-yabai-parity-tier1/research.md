# Research — SPEC-016 Yabai-parity tier-1

**Status**: Done
**Last updated**: 2026-05-02

## R-001 : Format TOML pour `[[rules]]` — array of tables vs table de listes

**Question** : comment représenter en TOML une liste ordonnée de règles avec champs nullable et matching premier-wins ?

**Décision** : `[[rules]]` (array of tables TOML standard, syntaxe officielle pour tableaux de structures). L'ordre du tableau dans le fichier est préservé par TOMLKit lors du parsing → cohérent avec le modèle "premier match wins" (FR-A1-03).

```toml
[[rules]]
app = "1Password"
title = "1Password mini"
manage = "off"

[[rules]]
app = "Slack"
space = 5

[[rules]]
app = "Activity Monitor"
float = true
sticky = true
```

**Rationale** :
- Pattern déjà utilisé dans le projet par `[[displays]]` (SPEC-012 `DisplayRule`). Cohérence interne.
- TOMLKit (déjà présent depuis SPEC-011) gère nativement `[[...]]` via `Codable` array.
- Lecture humaine triviale (`cat ~/.config/roadies/roadies.toml | grep -A5 '\[\[rules\]\]'`).

**Sources** :
- TOML 1.0.0 spec — array of tables
- `Sources/RoadieCore/Config.swift:151` — `DisplayRule` SPEC-012 utilise déjà ce pattern

**Alternatives évaluées** :
| Alternative | Verdict |
|---|---|
| JSON array dans le TOML (`rules = [{...}, {...}]`) | Moins lisible, moins idiomatique TOML, perte du commentaire par rule |
| Fichier dédié `~/.config/roadies/rules.toml` | Disperse la config (constitution principe E préfère fichier unique). Reporté à V2 si > 50 rules |
| YAML | Refusé par constitution principe E (TOML obligatoire) |

---

## R-002 : Regex matching pour `app` et `title` — quel moteur, quand compiler

**Question** : quel moteur regex pour les filtres `app=...` et `title=...` ? Compilation au parsing ou lazy ?

**Décision** : `NSRegularExpression` (Foundation) avec compilation **eager au parsing** (cache le `NSRegularExpression?` dans la struct `RuleDef`).

**Sémantique du champ `app`** :
- Si la chaîne ne contient aucun méta-caractère regex (`.`, `*`, `^`, `$`, `[`, `(`, `?`, `+`, `\`, `|`) → match exact case-insensitive sur `bundleID` ou `localizedName` (compatibilité yabai `app="Activity Monitor"` literal).
- Sinon → compilation regex case-insensitive `[.caseInsensitive]` puis `firstMatch(in: bundleID, ...)` ET `firstMatch(in: localizedName, ...)`.

**Rationale** :
- `NSRegularExpression` est dans Foundation, zéro dépendance ajoutée.
- Compilation eager : si une rule est cassée (regex invalide), on le détecte au boot et on log + skip — pas au runtime à chaque `window_created`.
- Heuristique métacaractères : reproduit la sémantique yabai (`app="Slack"` literal) sans forcer l'utilisateur à échapper.
- Cas insensible par défaut : aligné sur l'usage macOS (les noms d'app ne sont pas case-sensitive).

**Sources** :
- Apple Developer — `NSRegularExpression` reference
- Yabai `rule_apply.c` — sémantique app/title match

**Alternatives évaluées** :
| Alternative | Verdict |
|---|---|
| Swift `Regex<Output>` (Swift 5.7+) | API plus jolie mais syntaxe regex Swift custom (PCRE-like mais pas identique). Risque de désaligner du muscle-memory yabai. Reporté V2 |
| RE2 / PCRE via package externe | Refusé constitution principe B (zéro dep) |
| Glob pattern (fnmatch) | Trop limitant (yabai users pushent des regex avancés `^.*Settings$`) |

**Compilation result type** :
```swift
public struct RuleDef: Codable, Sendable {
    public let app: String?
    public let title: String?
    private let _appRegex: NSRegularExpression?      // nil si match literal
    private let _titleRegex: NSRegularExpression?
    // ...
}
```

`_appRegex == nil` ET `app != nil` ⇒ literal match.
`_appRegex != nil` ⇒ regex match.

---

## R-003 : Anti-pattern detection — refus de `app=".*"` au parsing

**Question** : comment détecter et refuser une rule trop large (qui matcherait toutes les fenêtres) ?

**Décision** : heuristique au parsing — une rule est rejetée si **au moins un de ces critères** est satisfait :
1. `app` matche la string vide (`regex.numberOfMatches(in: "", ...) > 0` → la regex est trop permissive)
2. `app == ".*"` ou `app == ".+"` ou `app == "^.*$"` (literal match contre la liste noire connue)
3. `title` est aussi vide/absente ET la rule contient `manage = "off"` ou `float = true` (combinaison "match all + désactiver" = incident garanti)

Une rule rejetée → **log error explicit** :
```
[rules] REJECTED rule #3: pattern 'app=".*"' would match all windows.
        Use specific app name or combine with title= filter.
        See ADR-006 §A1 for valid examples.
```

**Rationale** :
- Pattern dangereux à 100 % d'incident utilisateur : un `app=".*", manage="off"` désactive tout le tiling silencieusement. Le user croit avoir cassé son daemon.
- Test sur la string vide est l'invariant mathématique d'une regex permissive (toute regex qui matche `""` matche aussi tout).
- Liste noire literal en complément : couvre les cas où la regex ne matche pas `""` mais reste pathologiquement large.
- Critère #3 est conservateur : on autorise `app=".*"` SI title= filtre est présent (pattern user "tous les apps mais seulement les Settings windows").

**Rationale du refus plutôt que warn** : la constitution D (fail loud) impose de ne pas accepter silencieusement un comportement dangereux. Mieux vaut refuser au boot et exiger correction que de laisser le système dans un état "tiling désactivé sans raison apparente".

**Sources** :
- Aucune littérature spécifique — extrait de l'expérience yabai (PR #1234 discussion sur le danger de `--add app="^.*$" manage=off`)

**Tests prévus** : `RuleEngineTests.swift` cas `reject_match_all_pattern_*` (5 patterns dangereux + 3 patterns acceptables limite).

---

## R-004 : Signal action exec async — `Foundation.Process` + timeout robuste

**Question** : comment exécuter une commande shell async sans bloquer le daemon, avec capture stdout/stderr et timeout strict ?

**Décision** :
1. Spawn via `Foundation.Process` détaché (pas de `pipe.read()` synchrone). 
2. `process.executableURL = URL(fileURLWithPath: "/bin/sh")` + `process.arguments = ["-c", action]`.
3. Env vars contextuelles fusionnées dans `process.environment` (cf. R-006 SignalEnvironment).
4. stdout/stderr → 2 `Pipe` capturés en mémoire (cap 16 KB chacun pour éviter explosion mémoire si action verbose).
5. Timeout via `DispatchSourceTimer` à 5 s (ou `[signals] timeout_ms`) :
   - À l'expiration : `process.terminate()` (SIGTERM).
   - Re-arme un timer +1 s : si toujours running → `kill(pid, SIGKILL)`.
   - Log warn avec stderr capturé tronqué à 1 KB.
6. `process.terminationHandler` capture exit code et publie un event interne `signal_action_completed` (utile pour debug, non exposé sur l'EventBus public).

**Rationale** :
- `Foundation.Process` est l'API officielle Apple pour spawn child process (équivalent posix `fork+exec`).
- Détaché = jamais d'attente synchrone côté daemon → constraint "NE DOIT PAS bloquer" (FR-A2-04).
- Timeout SIGTERM puis SIGKILL = pattern standard daemons unix (donne 1 s de grâce pour cleanup propre, puis force).
- Cap 16 KB stdout/stderr : protège contre une commande qui inonde de logs.

**Sources** :
- Apple Developer — `Foundation.Process` reference
- yabai `signal_handler.c` — pattern similaire mais en C

**Alternatives évaluées** :
| Alternative | Verdict |
|---|---|
| `popen()` C bridged | Plus bas niveau, gestion timeout plus complexe, pas d'avantage |
| Swift `async let` + `Process.run()` await | Idiomatique Swift mais `await` bloque la Task, complexifie la coordination avec timeout. Le pattern callback-based reste plus simple |
| Tâche scheduled via `DispatchQueue.global().async` | Moins de contrôle sur le child process, ne facilite pas le SIGKILL au timeout |

---

## R-005 : Signal queue cap — Deque + drop FIFO

**Question** : comment éviter d'accumuler une queue infinie d'events si l'EventBus pousse plus vite que les actions shell n'exécutent ?

**Décision** : 
- `SignalDispatcher` maintient une queue interne `Deque<DesktopEvent>` (Swift Collections — déjà présent indirectement via Apple frameworks ou implémenté en interne 30 LOC).
- Cap 1000 entries (configurable `[signals] queue_cap`).
- Insertion : si `queue.count >= 1000` → drop l'élément en tête (oldest first FIFO) + log warn `[signals] queue saturated, dropping oldest event (%s)`.
- Worker async : pop tail (LIFO côté processing? non — FIFO pour préserver l'ordre causal) → match contre les `SignalDef` chargés → si match, exec async (R-004).

**Rationale** :
- Cap dur évite OOM en cas de bug user (action shell qui prend 30 s avec 1000 events/s = mémoire infinie sinon).
- Drop oldest = FIFO classique. Hypothèse : les events les plus récents sont plus utiles que les anciens (cohérent avec l'usage UI/notification).
- 1000 = ordre de grandeur raisonnable : 100 events/s × 10 s de retard absorbé.

**Justification d'une `Deque`** vs `Array` : `Array.removeFirst()` est O(n). `Deque.popFirst()` est O(1). À 1000 entries, la différence se mesure (~10 µs vs 10 ns).

**Implémentation Deque** : si Swift Collections (`swift-collections`) pas dispo, implémenter en interne avec un buffer circulaire (~30 LOC — sous le seuil constitution A).

**Tests prévus** : `SignalDispatcherTests.swift` cas `queue_drops_oldest_when_saturated` (push 1500 events, vérifier que les 500 premiers sont droppés, log warn émis).

---

## R-006 : Re-entrancy guard — flag `_inside_signal` thread-local

**Question** : comment empêcher qu'une action shell qui crée une fenêtre déclenche un signal en cascade infini ?

**Décision** :
- Flag `_inside_signal: Bool` propagé via `ThreadLocal<Bool>` (ou plus précisément, propagé sur le contexte Task Swift via `TaskLocal<Bool>`).
- Avant exec d'une action, le `SignalDispatcher` set `_inside_signal = true`.
- L'action shell exec via `/bin/sh -c` hérite de `ROADIE_INSIDE_SIGNAL=1` env var.
- Si l'action invoque `roadie window ...` qui parle au daemon, le daemon **détecte** l'env var dans la requête (transmise via socket dans le payload `_inside_signal: true`), et **ne déclenche pas** de SignalDispatcher pour les events qui résultent de cette commande.

**Mécanisme côté daemon** :
- `CommandRouter.route(request, ...)` lit `request._inside_signal` (propagé depuis le payload IPC).
- Si `true`, les events publiés sur `EventBus` pendant cette commande sont **flaggés** `payload["_inside_signal"] = "1"`.
- `SignalDispatcher.handleEvent(event)` skip silencieusement les events avec ce flag.

**Rationale** :
- Cascade infinie = bug catastrophe : 1 event → 1 action shell → ouvre fenêtre → 1 event → ... = fork bomb daemon.
- Re-entrancy guard est le pattern standard (irq handlers OS, callbacks UI).
- Propagation par env var puis par socket payload évite de devoir tracker l'état "dans-quelle-action-shell-suis-je" — c'est l'action elle-même qui se signale.

**Limitation acceptée** : si l'action shell lance un programme qui **lui-même** lance `roadie` sans propager l'env var (ex: `nohup`, `setsid`), la cascade pourrait reprendre. C'est documenté comme contre-pattern dans `quickstart.md` § "ne pas faire".

**Sources** :
- Pattern OS irq handler reentrancy
- yabai `signal_event_dispatch` ne fait PAS ce check (vulnerability connue) — on fait mieux

**Tests prévus** : `SignalDispatcherTests.swift` cas `reentrancy_guard_prevents_cascade` (signal sur `window_created` qui exec `roadie window close <focused>` → ne doit PAS déclencher un autre signal sur le `window_destroyed` résultant).

---

## R-007 : MouseFollowFocus implementation — polling 50 ms vs CGEventTap

**Question** : comment détecter le hover du curseur sur une fenêtre pour `focus_follows_mouse` sans demander une permission supplémentaire ni alourdir le système ?

**Décision** : **polling 50 ms** via `Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true)` qui appelle `NSEvent.mouseLocation`, teste l'inclusion dans une `WindowState.frame` du registry, et déclenche `FocusManager.setFocus(...)` après `idle_threshold_ms` (200 par défaut) d'immobilité.

**État interne** :
```swift
struct MouseFollowState {
    var lastCursorPos: NSPoint
    var lastMoveAt: Date
    var currentHoverWindow: CGWindowID?
    var dragActive: Bool             // exposé par MouseInputCoordinator
}
```

**Rationale** :
- `NSEvent.mouseLocation` est une **propriété publique** qui ne nécessite **aucune permission** (cohérent avec EdgeMonitor SPEC-014 R-003).
- 50 ms = 20 Hz, suffisant pour percevoir l'idle (200 ms = 4 polls). Coût CPU mesuré chez `EdgeMonitor` SPEC-014 : ~0.5 % à 12 Hz, donc ~0.8 % à 20 Hz. Acceptable.
- Le `MouseInputCoordinator` (cf. R-008 implicite) expose le flag `dragActive` issu de `MouseDragHandler` SPEC-015 → quand drag actif, le watcher est suspendu (`return early` dans le tick du timer).
- Pas de `CGEventTap` qui exigerait Input Monitoring permission **supplémentaire** spécifique au tap (≠ celui de SPEC-015 qui est sur `addGlobalMonitorForEvents`).

**Alternative évaluée — mutualiser `addGlobalMonitorForEvents` SPEC-015** :
- Pro : le hook existe déjà, pas de timer additionnel.
- Con : le hook reçoit `mouseMoved` events à fréquence native (60+ Hz), surcharge inutile pour `focus_follows_mouse` qui veut juste l'idle.
- Décision : **ne pas mutualiser le hook event-by-event, mais mutualiser le flag `dragActive`**. Le polling reste indépendant. Bonus : si demain on veut désactiver SPEC-015 sans casser SPEC-016, c'est trivial.

**Optimisation V2** : si profiling production montre une régression CPU > 1 %, basculer sur `addLocalMonitorForEvents` (notre app) + `addGlobalMonitorForEvents` (autres apps) avec un debounce 200 ms côté daemon.

**Sources** :
- SPEC-014 R-003 (polling 80 ms validé en production rail)
- Apple Developer — `NSEvent.mouseLocation`, `CGWarpMouseCursorPosition`

**Tests prévus** : `MouseFollowFocusWatcherTests.swift` couvre :
- `autofocus_after_idle_200ms`
- `no_focus_during_jitter` (curseur en mouvement continu pendant 1 s)
- `suspended_during_drag` (mock `dragActive = true`)
- `ignore_dock_menubar_zones`

---

## R-008 : Insert hint TTL et lifecycle — Map mémoire daemon

**Question** : comment représenter le hint `--insert <direction>` qui doit survivre 120 s entre la commande user et la création de la prochaine fenêtre ?

**Décision** :
- `InsertHintRegistry` : `@MainActor`, owns une `[CGWindowID: InsertHint]` map.
- À l'invocation `roadie window insert <dir>` : lire `focusedWindowID`, créer `InsertHint(targetWid: focusedWid, direction: dir, expiresAt: Date() + 120)`, écrire dans la map.
- Au `window_created` event : `LayoutEngine.insert(newWid, ...)` appelle d'abord `hintRegistry.consume(parentWid:)`. Si hint trouvé ET `Date() < expiresAt` ET hint dans le tree de la nouvelle fenêtre → applique la direction. Sinon → fallback algo split-largest standard.
- Garbage collection : `Timer` de 30 s qui purge les hints expirés (évite la map qui grossit indéfiniment si user pose 100 hints sans les consommer).
- Cleanup orphelin : si la fenêtre cible (`targetWid`) est détruite avant consommation → `EventBus.subscribe(.window_destroyed)` → remove le hint.
- Cleanup au tiler change : si `tiler.set` change la stratégie → flush tous les hints + log info "hint cancelled by strategy change".

**Sémantique précise du `consume`** :
- "Dans le tree de la nouvelle fenêtre" = la nouvelle fenêtre est dans le même `LayoutTree` (même display, même desktop) que `targetWid`. SPEC-012 multi-display garantit qu'il y a 1 tree par display.
- Si la nouvelle fenêtre apparaît sur un AUTRE display, le hint reste actif (l'user voulait split sur display 1, la fenêtre est apparue sur display 2 — pas la cible).

**Rationale** :
- TTL 120 s = ordre de grandeur "j'ai posé un hint, je vais ouvrir une fenêtre sous quelques secondes". Au-delà, l'intention est probablement perdue.
- Hint runtime mémoire (pas de persistance) : cohérent avec l'UX éphémère. Daemon redémarre = hints perdus = OK.
- Le `consume` côté `LayoutEngine.insert()` est synchrone, pas de race possible avec le GC timer.

**Sources** :
- yabai `--insert` est purement runtime (vérifié dans le code source `display_manager.c`)
- Pattern UI hint généralisé (Hyprland, sway, KWin)

**Tests prévus** : `InsertHintRegistryTests.swift` couvre :
- `consume_within_ttl_returns_hint`
- `consume_after_ttl_returns_nil`
- `orphan_cleanup_on_target_destroyed`
- `flush_on_strategy_change`
- `consume_only_for_same_tree`

---

## Verdict Phase 0

8 décisions techniques verrouillées. Aucune `NEEDS CLARIFICATION` ne subsiste. Le plan peut passer en Phase 1 (data model + contracts détaillés) sans blocage.

**Risques résiduels** (transférés en Risks & Mitigations du plan) :
- R-007 polling CPU si scope > 20 Hz nécessaire — fallback CGEventTap documenté pour V2
- R-006 cascade re-entrancy si user wraps `nohup` — documenté comme contre-pattern user
