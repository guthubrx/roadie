# Feature Specification: RoadieShadowless (SPEC-005)

**Feature Branch**: `005-shadowless`
**Created**: 2026-05-01
**Status**: Draft
**Dependencies**: SPEC-004 fx-framework (loader + RoadieFXCore + roadied.osax) doit être livré et stable avant impl
**Input** : « Premier module FX simple, proof-of-concept du framework SIP-off. Désactive l'ombre des fenêtres tierces (effet "tiling Linux clean"). Modes : `all` (toutes), `tiled-only` (les non-floating uniquement), `floating-only`. Densité paramétrable 0.0-1.0. Hot-reload via `roadie daemon reload`. Plafond LOC strict : 120 (cible 80). »

---

## Vocabulaire

- **Module RoadieShadowless** = `.dynamicLibrary` SwiftPM séparé, `libRoadieShadowless.dylib` chargé au runtime par le daemon via le framework SPEC-004.
- **Ombre fenêtre** = ombre portée que macOS dessine sous chaque NSWindow par défaut (≈ 16-32 px de gradient sombre autour de la fenêtre).
- **Density** = paramètre [0.0, 1.0] passé à `CGSSetWindowShadowDensity` via osax. 0.0 = invisible, 1.0 = défaut macOS.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Tiling clean façon Linux (Priority: P1) 🎯 MVP

L'utilisateur Bob a SIP partial off, framework SPEC-004 installé. Il fait `cp libRoadieShadowless.dylib ~/.local/lib/roadie/` puis `roadie daemon reload`. Sa config :

```toml
[fx.shadowless]
enabled = true
mode = "tiled-only"
density = 0.0
```

Au prochain tile (BSP réorganise), toutes les fenêtres tilées perdent leur ombre. Les fenêtres floating (notifications, alertes, dialogs) gardent leur ombre. Effet visuel : tiling très propre, lignes nettes entre tuiles, ressemble à i3wm ou Sway.

**Why this priority** : c'est l'effet visuel le plus demandé pour le tiling sur macOS, et c'est le module le plus simple → idéal pour valider le pipeline framework SPEC-004 end-to-end avec un effet réellement perceptible.

**Independent Test** : SIP off + framework + module installés, ouvrir 4 apps tilées + 1 dialog floating, vérifier visuellement que les 4 tilées n'ont pas d'ombre et le dialog en a une.

**Acceptance Scenarios** :
1. **Given** module activé `mode = "tiled-only"`. **When** une fenêtre est tilée par BSP. **Then** son ombre disparaît dans les 100 ms (1 tick AnimationLoop).
2. **Given** la même config. **When** une notification floating apparaît. **Then** elle garde son ombre (mode tiled-only ne touche pas les floating).
3. **Given** `mode = "all"`. **When** n'importe quelle fenêtre apparaît. **Then** son ombre disparaît, peu importe son statut (tilée ou floating).
4. **Given** `mode = "floating-only"`. **When** une notification apparaît. **Then** son ombre disparaît, les tilées gardent la leur.

---

### User Story 2 - Hot-reload sans redémarrage (Priority: P2)

L'utilisateur change `density = 0.0` → `density = 0.3` dans `roadies.toml`, fait `roadie daemon reload`. Toutes les fenêtres tilées passent à ombre 30 % (visuellement subtile mais présente). Pas de redémarrage daemon, pas de crash, transition en < 200 ms.

**Why this priority** : confort utilisateur typique pour ajuster un effet visuel.

**Independent Test** : changer la valeur de density, faire `daemon reload`, vérifier visuellement que les ombres existantes s'adaptent.

**Acceptance Scenarios** :
1. **Given** `density = 0.0` actif. **When** l'utilisateur passe à `density = 0.5` puis reload. **Then** les fenêtres tilées affichent une ombre à 50 % en moins de 200 ms.
2. **Given** module activé. **When** l'utilisateur passe `enabled = false` puis reload. **Then** toutes les fenêtres retrouvent leur ombre par défaut macOS dans la seconde.

---

### User Story 3 - Désactivation propre (Priority: P3)

L'utilisateur retire le `.dylib` de `~/.local/lib/roadie/`, fait `roadie daemon reload`. Toutes les fenêtres récupèrent leur ombre par défaut macOS sans intervention manuelle.

**Why this priority** : garantit la réversibilité totale.

**Independent Test** : `rm libRoadieShadowless.dylib` + `daemon reload`, vérifier que les ombres reviennent.

**Acceptance Scenarios** :
1. **Given** module installé et actif. **When** l'utilisateur retire le `.dylib` + reload. **Then** le module appelle `shutdown()` qui restaure les ombres via `set_shadow density=1.0`. Le module est ensuite déchargé.

---

### Edge Cases

- **osax indisponible** : OSAXBridge en queue, mais comme c'est un effet purement esthétique, drop silencieux après 5 secondes plutôt qu'attendre indéfiniment. Log warning au boot.
- **Fenêtre detruite pendant l'envoi** : `wid_not_found` côté osax → log info, ignore (pas un bug).
- **Trop de fenêtres** : si > 100 fenêtres ouvertes, on batch les `set_shadow` par paquets de 20 (1 batch / 16ms = 60 FPS) pour ne pas saturer le main thread Dock.
- **Mode mal écrit** : si `mode = "foobar"` dans config → log error au reload, mode forcé à valeur précédente (ou défaut `tiled-only` au boot).
- **density hors range** : si `density = 2.0` ou `-0.5` → clamp dans [0, 1] silencieusement, pas d'erreur (pas la peine de bloquer).
- **Module activé mais SIP fully on** : OSAXBridge ne se connectera pas, le module log warning au boot et tous ses appels sont des no-op. Pas de crash, daemon stable.

---

## Requirements

### Functional Requirements

- **FR-001** : Le module DOIT s'enregistrer auprès de l'EventBus aux events `window_created`, `window_focused`, `stage_changed`, `desktop_changed`, et tous les events qui peuvent changer le statut tile/floating d'une fenêtre.
- **FR-002** : Sur chaque event matching, le module DOIT déterminer la cible (selon `mode`) et envoyer `OSAXCommand.setShadow(wid, density)` via `OSAXBridge`.
- **FR-003** : 3 modes supportés : `all`, `tiled-only` (défaut), `floating-only`. Toute autre valeur de mode est rejetée au reload avec log error.
- **FR-004** : `density` ∈ [0.0, 1.0]. Valeurs hors range clampées silencieusement.
- **FR-005** : Au `shutdown()`, le module DOIT restaurer l'ombre par défaut (`set_shadow density=1.0`) sur **toutes** les fenêtres qu'il avait modifiées. Pas d'effet rémanent post-désactivation.
- **FR-006** : Le module DOIT supporter le hot-reload : sur `roadie daemon reload`, recharger la config `[fx.shadowless]` et appliquer les changements sur toutes les fenêtres concernées.
- **FR-007** : Si `enabled = false` dans config : module reste chargé mais inactif, ne consomme aucun event, ne fait aucun appel OSAX.

### Configuration

```toml
[fx.shadowless]
enabled = true
mode = "tiled-only"   # all | tiled-only | floating-only
density = 0.0         # 0.0 .. 1.0
```

### Key Entities

- **`ShadowlessModule`** : conform à `FXModule`, expose `module_init` via `@_cdecl`, contient un singleton `ShadowlessModule.shared`
- **`ShadowMode`** (enum) : `.all` | `.tiledOnly` | `.floatingOnly`
- **`TrackedWindow`** : `(wid, lastDensity)` pour pouvoir restaurer au shutdown

---

## Success Criteria

### Measurable Outcomes

- **SC-001** : Latence event → shadow updated ≤ **100 ms** (1 tick d'AnimationLoop = 16 ms + queue OSAX)
- **SC-002** : Précision visuelle : `density = 0.0` → ombre absolument invisible (vérification visuelle directe)
- **SC-003** : Reload via `daemon reload` propage la nouvelle config en moins de **200 ms** sur toutes les fenêtres concernées
- **SC-004** : Désinstallation : 100 % des fenêtres récupèrent leur ombre par défaut au shutdown (vérification : visuel + log shutdown count)
- **SC-005** : LOC effectives ≤ **120 strict** (cible 80). Mesure :
  ```bash
  find Sources/RoadieShadowless -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  ```
- **SC-006** : Aucune dépendance externe nouvelle (juste `RoadieFXCore` qui est déjà là via SPEC-004)
- **SC-007** : 0 crash sur 24h d'utilisation continue

---

## Assumptions

- SPEC-004 framework livré et stable depuis ≥ 2 semaines
- L'utilisateur a SIP partial off et osax installée
- Le daemon `roadied` est en mesure de fournir l'info `isFloating` sur chaque fenêtre via son `WindowRegistry` (déjà présent en SPEC-002)

---

## Out of Scope (SPEC-005 strict)

- **Customisation par-app** (genre "Slack toujours density 0.5") : reporté à SPEC-005.1 si demande forte
- **Animation de la transition density** : ombre change instantanément, pas de fade. Si on veut fade, c'est SPEC-007 RoadieAnimations qui fournira l'animation
- **Restauration partielle** : si user retire le `.dylib` pendant que daemon tourne, on ne fait pas de heroïque "détecter et restaurer". User doit faire `roadie daemon reload` après. (Le daemon ne surveille pas le filesystem en V1.)
- **Variations rim/glow** : SC-005 limite à density seulement. Le rim/glow CGS reste à valeur par défaut macOS
