# Research — SPEC-015 Mouse modifier drag & resize

**Date** : 2026-05-02 | **Phase** : 0

## Décisions techniques

### R1 — `NSEvent.addGlobalMonitorForEvents` vs CGEventTap

**Decision** : `NSEvent.addGlobalMonitorForEvents(matching:)` avec masques `[.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]`.

**Rationale** :
- Pattern déjà utilisé par `MouseRaiser` → permission Input Monitoring déjà acquise, pas de nouvelle prompt système.
- Suffisant pour observer les events souris **non-consumed** par d'autres apps. Quand une fenêtre app accepte un click, NSEvent global voit toujours l'event (vs CGEventTap qui peut le consommer).
- Évite la complexité de CGEventTap qui demande une accessibility plus large (`kIOHIDRequestTypeListenEvent` + `kIOHIDRequestTypePostEvent`).
- Latence acceptable (~5-10ms vs CGEventTap ~1-2ms) pour drag fluide.

**Alternatives** :
- CGEventTap : moins de latence mais plus complexe, plus de permissions, et risque de "voler" les clics utilisateur normaux.
- Polling de `NSEvent.mouseLocation` à 60Hz : coûteux CPU.

---

### R2 — Détection du quadrant pour resize

**Decision** : algo discrétisé en 8 zones (T, TR, R, BR, B, BL, L, TL) selon la position du clic dans le rect de la fenêtre :

```
let dx = (cursor.x - frame.minX) / frame.width  // 0..1
let dy = (cursor.y - frame.minY) / frame.height // 0..1
let edge = config.edgeThreshold / max(frame.width, frame.height)
// Zones :
//   coin top-left si dx < 1/3 et dy < 1/3
//   coin top-right si dx > 2/3 et dy < 1/3
//   ...
//   centre → tomber sur le quadrant nearest après 1er pixel de drag
```

**Rationale** :
- Modèle prévisible et stable (yabai utilise un schéma similaire).
- Pas besoin d'animation transitions entre quadrants (l'ancre est figée au mouseDown).
- `edge_threshold` (par défaut 30 px) configure la sensibilité côté bord.

**Alternatives** :
- Resize uniforme depuis le centre : non-intuitif, non implémenté V1.
- Resize 4 quadrants seulement (corners only) : moins puissant.

---

### R3 — Throttling setBounds

**Decision** : throttle `setBounds` à 30ms minimum entre 2 calls (= ≤33 FPS), via timestamp `Date()` comparé sur chaque mouseDragged.

**Rationale** :
- AX `setBounds` est une syscall ~2-5ms par call.
- Sans throttle, 60-120 mouseDragged/sec produiraient un appel inutile à chaque event.
- 30 FPS perçu suffit pour un drag fluide visuellement.
- Le **dernier** event mouseDragged avant mouseUp **doit** être appliqué (sinon la position finale est désynchro). Géré au mouseUp avec un setBounds final inconditionnel.

---

### R4 — Sortir du tile au début d'un move

**Decision** : au premier mouseDragged d'un drag-move sur une fenêtre tilée, appeler `LayoutEngine.removeWindow(wid)` + `registry.update { $0.isFloating = true }`. Pas de retour automatique au tile au mouseUp.

**Rationale** :
- yabai/AeroSpace font pareil (drag = sortie du tile).
- Logique : si l'utilisateur drag, il veut une position libre, pas un re-tile auto qui annule son geste.
- Pour re-tile, il a `roadie window toggle floating`.

**Alternatives** :
- Auto-retile au mouseUp si la fenêtre est dans une zone "tilable" : trop magic, source de surprise.

---

### R5 — Conflit avec MouseRaiser

**Decision** : ajouter dans `MouseRaiser.handleClick(at:)` un check `event.modifierFlags.intersection(activeModifier)`. Si match, skip le raise (= return early avant la logique raise).

**Rationale** :
- Solution la moins invasive : MouseRaiser monitor reste actif, juste skip le traitement quand le modifier est pressé.
- L'utilisateur peut toujours cliquer pour raiser sans modifier (= comportement actuel préservé).

**Alternatives** :
- Désactiver complètement MouseRaiser quand drag handler actif : moins flexible.
- Faire MouseRaiser et Drag handler partager un même monitor : refactor large, gain marginal.

---

### R6 — Fenêtre cross-display pendant le drag

**Decision** : pendant le drag, la fenêtre suit le curseur via setBounds. Si le centre de la fenêtre passe sur un autre display, **on ne fait rien de spécial pendant** (= la fenêtre est simplement à la position curseur, peut chevaucher 2 displays). Au mouseUp, on calcule le display final via le centre de la frame finale et on délègue à la logique SPEC-013 `onDragDrop` (= adoption desktop si mode per_display).

**Rationale** :
- Cohérent avec l'expérience standard macOS (drag d'une fenêtre entre Spaces visuels).
- Évite des bascules de tile/desktop pendant le drag (= jitter visuel).

---

### R7 — Permission Input Monitoring absente

**Decision** : au boot, si `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` retourne `false`, logger une erreur explicite (« mouse drag/resize disabled — grant Input Monitoring permission to roadied.app ») et **skip l'init de MouseDragHandler** (mais ne pas crasher). MouseRaiser est aussi désactivé dans ce cas (déjà géré).

**Rationale** :
- Constitution principe D (fail loud, no fallback silencieux).
- L'utilisateur peut accorder la permission et redémarrer le daemon.

---

## Coût implémentation et risque

**Estimation** :
- Code Swift : ~300 LOC effectives.
- Tests : 3 fichiers (~150 LOC).
- Risque principal : conflit avec apps qui utilisent Ctrl+click natif (= macOS Right Click). Mitigation : modifier configurable, l'utilisateur peut choisir Alt si conflit.
- Risque secondaire : fluidité du drag dépend de la perf AX setBounds, qui peut varier selon l'app cible (Electron lent vs natif rapide). Mitigation : throttle 30ms + acceptation du "best effort".
