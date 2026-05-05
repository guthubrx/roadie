# Research — SPEC-026 WM-Parity

## Décisions techniques

### R1 — Monitor `mouseMoved` global sans race avec drag

**Décision** : `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` + check `MouseDragHandler.isDragging` avant action. Throttle 100ms via `Date()` lastApply pattern.

**Rationale** : pattern déjà éprouvé dans `MouseDragHandler.swift` du projet. Ne nécessite aucune permission au-delà d'Accessibility déjà accordée. `addGlobalMonitorForEvents` est passive (lecture only), n'interfère pas avec d'autres apps.

**Alternatives considérées** :
- `CGEventTap` : plus puissant mais nécessite Accessibility + un thread dédié, complexité accrue. Rejeté car overkill pour notre besoin.
- Polling timer : 60Hz polling sur `NSEvent.mouseLocation` — gaspille CPU, latence pire. Rejeté.

### R2 — Warp curseur sans interrompre AX

**Décision** : `CGWarpMouseCursorPosition(point)` (CoreGraphics, déjà importé).

**Rationale** : API publique macOS, déplace le curseur instantanément sans synthétiser d'event souris. Le focus AX reste intact.

**Alternatives considérées** :
- `CGEventCreateMouseEvent` + post : crée un mouseMoved synthétique → re-déclenche notre watcher → feedback loop. Rejeté.
- `CGAssociateMouseAndMouseCursorPosition(false)` : décorrèle curseur et device — confus pour utilisateur. Rejeté.

### R3 — Process shell async fire-and-forget avec timeout 5s

**Décision** : `Process` Foundation + `Task` async + `DispatchQueue.global().asyncAfter(deadline: .now() + 5)` qui appelle `process.terminate()` si encore running, puis `process.interrupt()` si toujours là (équivalent SIGTERM puis SIGKILL).

**Rationale** : Foundation standard, pas de dépendance. Pattern fire-and-forget : pas de capture stdout/stderr (économie mémoire), juste exit code logué.

**Alternatives considérées** :
- Shell direct via `system()` : bloquant, no timeout. Rejeté.
- Lancement via `launchctl bsexec` : trop complexe. Rejeté.

### R4 — Matcher la fenêtre produite par `cmd` du scratchpad

**Décision** : Watch `EventBus.window_created` pendant 5s post-spawn ; prendre la 1ère wid avec `bundleID` matchant le binaire de `cmd` (heuristic : `open -na 'iTerm'` → bundleID `com.googlecode.iterm2`). Si `match.bundle_id` est explicite dans la `[[scratchpads]]` def, l'utiliser à la place de l'heuristic.

**Rationale** : pattern proche de yabai `--criteria` (matching après spawn). L'heuristique sur `open -na 'AppName'` couvre 80% des cas usuels. Override explicite via `match.bundle_id` pour les cas plus complexes.

**Alternatives considérées** :
- Lancement via `Process.launchPath` + récupération PID + scan windows par PID : plus précis mais nécessite mapping PID→bundleID complexe. Reporté en SPEC future si besoin.
- Demander à l'utilisateur de toujours fournir `match.bundle_id` : friction UX. Rejeté.

### R5 — Anti-feedback loop focus_follows_mouse ↔ mouse_follows_focus

**Décision** : flag `inhibitFollowMouseUntil: Date?` posé par `mouse_follows_focus` (CGWarp) à `Date() + 0.2s`. Vérifié au début du handler `focus_follows_mouse` (skip si `Date() < inhibitFollowMouseUntil`).

**Rationale** : 200ms est largement supérieur au throttle 100ms du watcher, garantit qu'au moins un cycle est inhibé. Implémentation 4 lignes.

**Validation tests** : test unitaire `FollowFocusTests.testNoFeedbackLoop` simule un focus change via raccourci suivi de N mouse moves dans la fenêtre 200ms → vérifie qu'aucun setFocus supplémentaire n'est déclenché.

**Alternatives considérées** :
- Désactiver focus_follows_mouse pendant un mouse_follows_focus via flag bool : pareil mais sans expiration auto, risque oubli de désactivation. Rejeté.
- Track le warp source via une métadonnée d'event : surcomplexité. Rejeté.

### R6 — Sticky scope=all cross-display

**Décision** : la wid `sticky_scope = "all"` est déplacée vers le display courant à chaque `display_changed` event. Pas de clonage visuel.

**Rationale** : impossible de cloner une fenêtre native macOS sans scripting addition (SIP-off). Le déplacement vers le display actif simule la "présence partout" d'une manière acceptable. Pattern documenté chez yabai (`yabai -m window --grid` + sticky).

**Alternatives considérées** :
- Pin to NSWindow.Level.floating : le rend always-on-top de tout, pas le comportement attendu. Rejeté.
- Hide complètement la wid sur les autres displays + show sur le courant : revient au même que déplacement, mais plus complexe et glitch visuel. Rejeté.

### R7 — Smart gaps detection per-display

**Décision** : dans `applyAll`, calculer `displayLeavesCount` pour chaque display avant le calcul des frames ; si `count == 1` et `smartGapsSolo == true`, override `gapsOuter` et `gapsInner` à 0 pour ce display uniquement.

**Rationale** : changement local dans la boucle existante, ~10 LOC. Per-display garantit qu'un display avec 1 fenêtre n'affecte pas un autre avec 3 fenêtres.

**Alternatives considérées** :
- Toggle global (gaps=0 partout si l'un des displays a 1 fenêtre) : non, on veut indépendance par display. Rejeté.

## Sources

- Apple `CGRemoteOperations.h` (CGWarpMouseCursorPosition).
- yabai docs : commandes `--balance`, `--rotate`, `--mirror`, `--criteria`, sticky behavior.
- Hyprland config docs : `smart_gaps`, `special_workspace`, `dispatcher signal`.
- Code source roadie : `Sources/RoadieCore/MouseDragHandler.swift` (pattern NSEvent monitor + isDragging), `Sources/RoadieStagePlugin/StageManager.swift` (pattern memberWindows projection).

## Confiance globale

Score : 0.92/1.0. Toutes les décisions s'appuient sur des patterns déjà en place dans le projet ou des APIs documentées Apple. Pas d'inconnu majeur restant.
