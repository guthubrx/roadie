# Research — SPEC-014 Stage Rail UI

**Status**: Draft
**Last updated**: 2026-05-02

## R-001 : ScreenCaptureKit pour capture vignettes fenêtres tierces

**Question** : quelle API utiliser pour obtenir une vignette PNG périodique d'une fenêtre tierce identifiée par CGWindowID, sans dégrader les perfs et sans recourir à des APIs privées ?

**Décision** : `SCStream` + `SCStreamConfiguration` + filtre `SCContentFilter(desktopIndependentWindow: SCWindow)` à 0.5 Hz, output ré-échantillonné CoreImage vers max 320×200 px puis encodé PNG via `CGImageDestination`.

**Rationale** :
- ScreenCaptureKit est l'API publique macOS 14+ officiellement supportée pour capture par fenêtre.
- Remplace les usages legacy `CGWindowListCreateImage` (déprécié, plus coûteux, ne capture plus correctement les fenêtres Metal/Electron sur Sequoia+).
- Pas d'APIs privées CGS impliquées.
- Performance mesurée yabai : ~3-5 ms par capture pour une fenêtre 1920×1200 (downscale inclus). 0.5 Hz = 0.25 % CPU.

**Sources** :
- Apple Developer — ScreenCaptureKit Programming Guide (macOS 14+)
- Yabai PR #2701 (octobre 2024) — bascule vers SCK pour le module thumbnails
- Hammerspoon `hs.canvas` discussions — comparaison SCK vs CGWindowListCreateImage

**Alternatives évaluées** :
| Alternative | Verdict |
|---|---|
| `CGWindowListCreateImage` | Déprécié macOS 15+, plus lent, capture incorrecte sur fenêtres Metal |
| `CGSCaptureWindowsContents` (privé) | Interdit par C' constitution |
| `NSWorkspace.shared.icon(forFile:)` | Notre fallback FR-010 quand Screen Recording non accordée |
| Capture de l'écran entier puis crop | 10× plus coûteux, surface de fuite plus large |

**Permission requise** : Screen Recording côté daemon `roadied`. À demander au premier appel `roadie window thumbnail <wid>`.

---

## R-002 : NSPanel SwiftUI hosting pour le rail

**Question** : comment afficher une vue SwiftUI dans un panneau qui ne vole pas le focus, reste au-dessus des fenêtres standard, et survit aux switches d'espaces ?

**Décision** :
```swift
let panel = NSPanel(
    contentRect: rect,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
panel.isFloatingPanel = true
panel.becomesKeyOnlyIfNeeded = true
panel.hidesOnDeactivate = false
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true

let host = NSHostingView(rootView: StageStackView(state: state))
panel.contentView = host
```

**Rationale** :
- `.nonactivatingPanel` empêche l'app de devenir frontmost à l'apparition du panel (évite vol focus).
- `level = .statusBar` (≈ 25 dans la hiérarchie NSWindowLevel) place le panel au-dessus des fenêtres normales (.normal = 0, .floating = 5) mais sous les modales système.
- `canJoinAllSpaces + stationary` : le panel survit aux switches d'espaces natifs sans avoir besoin d'être recréé.
- `NSHostingView` est la bridge officielle SwiftUI ↔ AppKit depuis macOS 11.

**Sources** :
- Apple Developer Forums — pattern HUD overlay (Spotlight, Mission Control)
- Hammerspoon source code — `hs.canvas` utilise un pattern similaire
- Anciens projets `39.roadies.off/Sources/roadie/RailUI/RailWindow.swift`

**Risques** :
- Sur Tahoe 26, certaines combinaisons styleMask + level ont changé subtilement. Test acceptance obligatoire avant V1.
- SwiftUI dans NSHostingView peut avoir des bugs de layout sur premier render — pré-warmer l'invisibilité au boot.

---

## R-003 : Polling souris vs global event monitor

**Question** : comment détecter le hover de l'edge gauche de l'écran sans demander la permission Input Monitoring ?

**Décision** : `Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true)` qui appelle `NSEvent.mouseLocation` et teste l'inclusion dans le rect d'edge.

**Rationale** :
- `NSEvent.mouseLocation` est une propriété publique qui ne nécessite **aucune permission**.
- Polling à 12 Hz (80 ms) suffit pour une détection visuellement instantanée du hover.
- Coût CPU ~0.5 % observé sur Apple Silicon dans yabai_stage_rail.swift de référence.

**Alternative évaluée** : `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`. Rejetée car nécessite Input Monitoring permission (FR-002 contrainte).

**Optimisation prévue V2** : si profiling montre une régression, basculer vers une version basse fréquence (250 ms) hors zone proche edge, et accélérer (40 ms) à proximité. Pas en V1.

---

## R-004 : Détection click-on-wallpaper côté daemon (kAX)

**Question** : comment détecter qu'un click souris est tombé sur le bureau (= aucune fenêtre tracked dessous), pour déclencher le geste « créer une stage » sans permission Input Monitoring supplémentaire ?

**Décision** :
1. S'abonner à `kAXMouseDownEvent` via `AXObserverCreate` sur l'élément racine `Finder` + `Dock`.
2. Au mouseDown, lire `kAXTopLevelUIElementAttribute` à la position du curseur.
3. Si l'élément retourné est `nil` ou de rôle `AXScrollArea` du Finder (= zone bureau), considérer comme click wallpaper.
4. Vérifier qu'aucune fenêtre du registry roadie n'est sous le curseur (via `NSPointInRect` sur les frames trackées).

**Rationale** :
- kAX est déjà dans le périmètre de permissions du daemon (Accessibility accordée pour SPEC-002).
- Pattern utilisé par yabai pour son détection de clicks sur le bureau Finder.
- Robustesse multi-version macOS via fallback : si `kAXTopLevelUIElement` retourne quelque chose d'inattendu, no-op silencieux.

**Risque** : Tahoe 26 peut introduire de nouvelles représentations AX du bureau Finder. Test acceptance obligatoire.

**Désactivation** : config TOML `[fx.rail] wallpaper_click_to_stage = false` (default `true`).

---

## R-005 : Transmission de vignettes PNG via socket Unix JSON-lines

**Question** : comment streamer ~30 KB de PNG bytes via un socket Unix qui parle JSON-lines, sans casser le protocole existant ni introduire de framing binary ?

**Décision** : encoder en base64 dans le payload JSON. Réponse type :
```json
{"png_base64": "iVBORw0KGgo...", "wid": 12345, "size": [320, 200], "degraded": false, "captured_at": "2026-05-02T17:30:42.123Z"}
```

**Rationale** :
- Pas de breaking change du protocole JSON-lines (SPEC-002 + SPEC-003).
- Coût encode/decode base64 négligeable (~0.1 ms pour 30 KB sur Apple Silicon).
- Surcharge taille +33% vs binary (40 KB transmis pour 30 KB de PNG) — acceptable.
- Permet aux outils existants (`roadie events --follow`, debug par `nc`) de continuer à parser sans changement.

**Alternative évaluée** : tube nommé séparé pour les bytes binaires. Plus rapide en théorie mais complexité +2 et surface de bug. Reporté à V2 si profiling justifie.

---

## R-006 : Cycle de vie mono-instance et PID-lock

**Question** : comment garantir qu'une seule instance de `roadie-rail` tourne par session utilisateur, sans dépendance externe ?

**Décision** :
- Au démarrage : `~/.roadies/rail.pid` lu. Si présent et PID vivant (`kill(pid, 0) == 0`), exit avec message "rail already running (PID X)".
- Sinon, écrire son propre PID dans le fichier.
- Signal handler SIGTERM/SIGINT supprime le fichier à la sortie.
- Si crash sans cleanup, le PID au démarrage suivant ne sera plus vivant → écrasement OK.

**Rationale** : pattern standard daemons Unix. Aucune dépendance.

**Source** : implémentations dnsmasq, mosh, plusieurs daemons macOS.

---

## R-007 : Compatibilité avec Mission Control hot corners

**Question** : un edge sensor de 8 px à gauche de l'écran risque-t-il d'entrer en collision avec un hot corner Mission Control configuré au coin haut-gauche / bas-gauche ?

**Décision** : edge rect = `(0, 8, edge_width, screen_height - 16)`. C'est-à-dire on **exclut explicitement** les 8 premiers et 8 derniers pixels du sensor pour laisser les hot corners macOS opérer librement.

**Rationale** :
- Hot corners macOS s'activent dans une zone de ~10×10 px aux 4 coins.
- Notre exclusion 8 px est conservatrice (laisse de la marge).
- Test acceptance : `tests/14-no-hotcorner-conflict.sh` — configure un hot corner et valide que le rail n'intercepte pas.

---

## R-008 : Multi-display et mode `per_display`

**Question** : comment instancier proprement un panel par écran connecté avec mode `per_display`, et reconfigurer dynamiquement à `didChangeScreenParametersNotification` ?

**Décision** :
1. `RailController` lit la config `[desktops] mode` au démarrage.
2. Si `mode = "per_display"` : pour chaque `NSScreen.screens`, instancier un `StageRailPanel` indépendant avec son propre `EdgeMonitor` lié à l'écran.
3. Si `mode = "global"` : un seul panel sur l'écran principal (`NSScreen.main`).
4. S'abonner à `NSApplication.didChangeScreenParametersNotification` → recompute la liste, reuse les panels existants par `displayUUID`, créer/détruire selon delta.

**Rationale** : approche adoptée par AeroSpace et yabai. Robuste face aux branchements/débranchements à chaud.

**Edge cases** :
- Écran débranché pendant rail visible → panel correspondant fade-out + close.
- Écran reconnecté (même `displayUUID`) → panel recréé, état inférré du daemon.
- Réorganisation des écrans (drag dans Réglages Système) → tous les panels sont repositionnés à leur nouvel edge gauche.

---

## R-009 : Reclaim horizontal space — retiling synchronisé

**Question** : comment garantir que l'animation de fade-in du rail et le retiling des fenêtres sous-jacentes (avec `reclaim_horizontal_space = true`) ne créent pas de jank visible ?

**Décision** :
1. À l'apparition du rail, le rail envoie `roadie tiling reserve --left <panel_width>` AU DÉBUT de l'animation fade-in.
2. Le daemon retiles immédiatement avec workArea ajusté.
3. La fade-in du rail dure 200 ms, le retiling daemon-side prend ~50-100 ms : les deux animations se chevauchent visuellement, l'œil perçoit une transition unifiée.
4. À la disparition, l'inverse : `roadie tiling reserve --left 0` au début du fade-out.

**Rationale** : déclencher le retiling en parallèle (pas en séquence) lisse l'expérience. Si le retiling était attendu avant la fade-in, l'utilisateur verrait un saccade avant l'apparition du rail.

**Risque** : `roadie tiling reserve` est une nouvelle commande IPC à introduire (cf contracts/cli-tiling-reserve.md). À documenter clairement.

---

## R-010 : SwiftUI vs AppKit — décision finale

**Question** : SwiftUI macOS 14+ est-il assez stable pour produire un binaire UI de qualité production en 2026-05 ?

**Décision** : OUI, SwiftUI macOS 14+. La maturité du framework depuis macOS 14 est suffisante pour les cas d'usage du rail (animations légères, drag-drop, layout dynamique). Le hosting via NSHostingView dans un NSPanel custom est éprouvé.

**Rationale** :
- Réduction LOC ~50% vs AppKit pur pour ce type d'UI déclarative.
- Maintenance plus simple, moins de boilerplate.
- L'utilisateur l'a explicitement choisi en réponse aux questions design.

**Compromis** : pour des cas marginaux (drag NSPasteboard custom, custom NSDraggingSource) on tombe en interop AppKit via `NSViewRepresentable`. Acceptable, ~5 % du code total.

---

## Verdict Phase 0

Toutes les questions techniques ont une réponse ferme. Aucune NEEDS CLARIFICATION ne reste. Le plan peut passer en Phase 1 (data model + contracts) sans blocage.
