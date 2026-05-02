# Feature Specification: Roadie Multi-Display

**Feature Branch**: `012-multi-display`
**Created**: 2026-05-02
**Status**: Draft
**Dependencies**: SPEC-001 (stage-manager), SPEC-002 (tiler-stage), SPEC-011 (virtual-desktops). Étend la mécanique multi-desktop pour la rendre consciente des écrans physiques.
**Input**: SPEC-011 traite déjà du hide multi-display (positions offscreen calculées dynamiquement via NSScreen.screens). Mais le **tiling** reste mono-écran : `LayoutEngine` distribue les fenêtres dans un seul rect (le primary). SPEC-012 étend roadie pour : (a) tiling indépendant par écran, (b) déplacement explicite de fenêtres entre écrans, (c) détection dynamique branch/débranch, (d) persistance de l'écran d'origine de chaque fenêtre, (e) CLI `roadie display *` et `roadie window display N`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Tiling indépendant par écran (Priority: P1)

L'utilisateur a un MacBook (écran 1, primary) et un écran externe 4K (écran 2). Sur l'écran 1, il veut un layout BSP avec ses fenêtres iTerm. Sur l'écran 2, il veut un master-stack avec son navigateur en master et plusieurs fenêtres de monitoring en stack. Aujourd'hui (SPEC-011), le tiler ne distribue qu'un seul rect (le primary) ; les fenêtres de l'écran 2 ne sont pas tilées par roadie. Avec SPEC-012, chaque écran a son propre arbre de tiling indépendant, avec sa propre stratégie configurable.

**Why this priority** : c'est la valeur principale pour les utilisateurs power-user multi-écran. Sans ça, le 2e écran reste "no man's land" non tilé.

**Independent Test** : ouvrir 2 fenêtres iTerm sur l'écran 1 et 2 fenêtres Firefox sur l'écran 2. Vérifier que iTerm tile en BSP sur l'écran 1 (chaque fenêtre prend une moitié de l'écran 1) et Firefox tile en master-stack sur l'écran 2 (Firefox 1 prend la grande partie, Firefox 2 prend le coin). Aucune fenêtre ne traverse la frontière entre écrans.

**Acceptance Scenarios** :

1. **Given** 2 écrans avec 2 fenêtres tileable chacun, layout BSP global, **When** une nouvelle fenêtre s'ouvre sur l'écran 2, **Then** elle est insérée dans l'arbre BSP de l'écran 2 et tilée avec les autres fenêtres de l'écran 2 — sans affecter le layout de l'écran 1.
2. **Given** config `[[displays]]` avec override `default_strategy = "master_stack"` pour l'écran 2 (matched par index), **When** le daemon démarre, **Then** l'écran 2 utilise master-stack tandis que l'écran 1 utilise la stratégie globale BSP.

---

### User Story 2 — Déplacer une fenêtre vers un autre écran (Priority: P1)

L'utilisateur a une fenêtre Slack sur l'écran 1, et il veut la déplacer sur l'écran 2 (4K) pour avoir plus d'espace. Il exécute `roadie window display 2` (ou ⌥+⇧+→ via BTT). La fenêtre se déplace physiquement vers l'écran 2, est retirée de l'arbre de tiling de l'écran 1 (le layout 1 est ré-appliqué pour combler l'espace), et insérée dans l'arbre de l'écran 2 (le layout 2 est ré-appliqué pour intégrer la nouvelle fenêtre).

**Why this priority** : pas de gestion multi-écran sans cette commande. Indispensable au quotidien.

**Independent Test** : 1 fenêtre tilée sur écran 1, exécuter `roadie window display 2` ; vérifier que la fenêtre apparaît sur l'écran 2, qu'elle est tilée selon la stratégie de l'écran 2, et que l'arbre de l'écran 1 n'a plus cette fenêtre.

**Acceptance Scenarios** :

1. **Given** fenêtre frontmost tileable sur l'écran 1, **When** `roadie window display 2`, **Then** la fenêtre est physiquement déplacée à l'écran 2 (sa frame intersecte le visibleFrame de l'écran 2), tilée selon la stratégie de l'écran 2, et n'apparaît plus dans l'arbre de l'écran 1.
2. **Given** fenêtre flottante (subrole `dialog`), **When** `roadie window display 2`, **Then** la fenêtre est déplacée à l'écran 2 sans tile (reste flottante au centre du visibleFrame).
3. **Given** index d'écran invalide (ex: 5 alors que 2 écrans), **When** `roadie window display 5`, **Then** erreur `unknown_display`, exit code 2.

---

### User Story 3 — Détection dynamique branch/débranch (Priority: P1)

L'utilisateur travaille avec MacBook + écran externe ; il débranche l'écran externe. Toutes les fenêtres qui étaient sur l'écran externe sont automatiquement migrées vers l'écran primary, leur frame réajustée pour rester dans le visibleFrame du primary. Le tiler de l'écran externe est dissous, son arbre fusionné dans celui du primary. À la reconnexion, les fenêtres restent sur le primary (le mapping vers l'écran externe est perdu après débranchement). Si l'utilisateur les redéplace manuellement vers l'écran externe, roadie reconstruit l'arbre de tiling de l'écran 2.

**Why this priority** : le branch/débranch est la réalité quotidienne en mobilité. Sans cette gestion, les fenêtres deviennent inaccessibles ou se positionnent hors-écran à la déconnexion.

**Independent Test** : 2 écrans avec fenêtres réparties, simuler un débranchement (changement de config affichage Réglages Système ou via `displayplacer`), vérifier que les fenêtres de l'écran 2 reviennent sur l'écran 1 dans le visibleFrame.

**Acceptance Scenarios** :

1. **Given** 2 fenêtres tilées sur l'écran 2, **When** l'écran 2 est déconnecté, **Then** les 2 fenêtres apparaissent sur l'écran 1 dans le visibleFrame (pas hors-écran), tilées avec les fenêtres existantes du primary.
2. **Given** debranchement → reconnexion d'un écran identique, **When** l'écran 2 revient, **Then** les fenêtres ne reviennent **pas** automatiquement (mapping perdu) ; l'utilisateur doit les redéplacer manuellement.

---

### User Story 4 — Lister les écrans (Priority: P1)

L'utilisateur veut voir les écrans connus de roadie pour scripter ou configurer. Il exécute `roadie display list` qui affiche : id, index, name, frame, visibleFrame, is_main (true/false pour le primary), is_active (true si l'écran contient la fenêtre frontmost), counts par desktop courant.

**Why this priority** : besoin de base pour scripter et debugger.

**Independent Test** : `roadie display list` doit retourner au moins 1 ligne (le primary), avec frame correspondant à `NSScreen.main.frame`.

**Acceptance Scenarios** :

1. **Given** mono-écran, **When** `roadie display list`, **Then** retourne 1 ligne `id=0 name=... is_main=true is_active=true windows=N`.
2. **Given** 2 écrans, **When** `roadie display list`, **Then** retourne 2 lignes triées par index ; au moins une `is_main=true` ; au moins une `is_active=true` (correspondant à l'écran qui contient la fenêtre frontmost).

---

### User Story 5 — Per-display config (Priority: P2)

L'utilisateur veut configurer son écran externe différemment du primary. Dans `roadies.toml` :

```toml
[[displays]]
match_index = 1                  # ou match_uuid / match_name
default_strategy = "master_stack"
gaps_outer = 16
gaps_inner = 8
```

Au boot ou au branchement de l'écran 2, ces overrides s'appliquent.

**Why this priority** : utile pour utilisateurs avancés mais pas bloquant pour l'usage de base.

**Independent Test** : config 2 displays avec stratégies différentes, vérifier que le tiling diffère par écran.

**Acceptance Scenarios** :

1. **Given** `[[displays]] match_index=1 default_strategy="master_stack"`, **When** boot, **Then** l'écran 2 utilise master-stack et l'écran 1 utilise la stratégie globale.

---

### User Story 6 — Events display_changed (Priority: P2)

SketchyBar (ou tout subscriber) veut afficher l'écran actif (celui qui contient la fenêtre frontmost). Quand l'utilisateur déplace son focus d'un écran à l'autre, un event `display_changed` est émis sur le canal `roadie events --follow`.

**Why this priority** : utile pour intégrations menu bar mais pas bloquant.

**Independent Test** : `roadie events --follow --types display_changed` ; déplacer une fenêtre/focus d'un écran à l'autre ; vérifier réception event JSON-line.

**Acceptance Scenarios** :

1. **Given** subscriber connecté, **When** focus passe de l'écran 1 à l'écran 2, **Then** un event `{"event":"display_changed","from":"0","to":"1","ts":...}` est écrit dans le stream.

---

### User Story 7 — Compatibilité ascendante mono-écran (Priority: P1)

Un utilisateur SPEC-011 mono-écran qui upgrade vers SPEC-012 ne voit aucun changement. Le code multi-display utilise `NSScreen.screens.count == 1` comme cas normal et délègue tout au primary screen, exactement comme avant.

**Why this priority** : promesse "zéro régression" — critique pour déploiement.

**Independent Test** : exécuter la suite de tests SPEC-011 complète sur SPEC-012 sans modification, tous tests verts.

**Acceptance Scenarios** :

1. **Given** mono-écran, **When** `roadie display list`, **Then** retourne 1 ligne identique.
2. **Given** mono-écran, **When** `roadie window display 2`, **Then** erreur `unknown_display` (cohérent avec out-of-range).

---

### Edge Cases

- **Fenêtre à cheval entre 2 écrans** : association à l'écran qui contient le centre de sa frame.
- **Fenêtre fullscreen native macOS** : ignorée par roadie (vit sur son propre Mac Space).
- **Écran principal change** (utilisateur change le primary dans Réglages Système) : recalcul transparent, frames réajustées si nécessaire.
- **Écran avec scaling Retina** : `frame` et `visibleFrame` sont en points logiques, pas pixels — pas de problème spécifique.
- **Écran portrait (rotation 90°)** : pris en charge nativement par NSScreen (frame.height > frame.width). Le tiler s'adapte au rect.
- **Écran à coordonnées négatives** (positionné à gauche du primary) : déjà géré par SPEC-011 pour le hide ; étendu au tiling.
- **Branche écran 2 pendant qu'une bascule de desktop est en cours** : la bascule termine sur la config courante, la nouvelle config s'applique au prochain refresh.
- **Plus de 4 écrans** : pas de limitation arbitraire ; performance dégrade linéairement (négligeable jusqu'à ~8 écrans).
- **Hot reload de la config `[[displays]]`** : pris en compte au prochain branch/débranch ou via `roadie daemon reload`.

## Requirements *(mandatory)*

### Functional Requirements

#### Détection et énumération

- **FR-001** : le système doit énumérer tous les écrans physiques connectés via `NSScreen.screens` et leur attribuer un id stable (basé sur `displayID` Quartz pour résister aux réorganisations).
- **FR-002** : le système doit observer `NSApplication.didChangeScreenParametersNotification` et recalculer son state à chaque changement de configuration d'écran (branchement, débranchement, repositionnement, changement de résolution).
- **FR-003** : `NSScreen.screens[0]` est le primary (`is_main = true`). L'index dans `roadie display list` est l'ordre dans `NSScreen.screens` (0..N-1).

#### Tiling per-display

- **FR-004** : chaque écran connecté possède son propre arbre de tiling indépendant (BSP, master-stack, ou floating selon la stratégie de l'écran).
- **FR-005** : à l'enregistrement d'une fenêtre, le système détermine son écran d'origine en testant quel `NSScreen.visibleFrame` contient le centre de sa frame ; la fenêtre est insérée dans l'arbre de cet écran.
- **FR-006** : `applyLayout()` global itère sur tous les écrans connectés et applique le layout de chacun dans son `visibleFrame` respectif.
- **FR-007** : la stratégie de tiling par écran peut différer (BSP sur écran 1, master-stack sur écran 2). Stratégie par défaut : globale (`config.tiling.default_strategy`). Override possible via `[[displays]]`.

#### Déplacement entre écrans

- **FR-008** : `roadie window display N` (où N est l'index 1-based de l'écran cible) déplace la fenêtre frontmost vers l'écran N — physiquement (frame ajustée pour intersecter le visibleFrame cible) et logiquement (retirée de l'arbre de l'écran source, insérée dans celui de l'écran cible).
- **FR-009** : si la fenêtre est tilée à la source, elle conserve `isTileable = true` et est tilée à destination. Si floating, elle reste floating et est positionnée au centre du visibleFrame cible.
- **FR-010** : si N est hors range `1..NSScreen.screens.count`, retourner erreur `unknown_display`.

#### CLI

- **FR-011** : `roadie display list` retourne pour chaque écran : id, index (1-based), name, frame, visible_frame, is_main, is_active, window_count (du desktop courant).
- **FR-012** : `roadie display current` retourne l'écran qui contient la fenêtre frontmost.
- **FR-013** : `roadie display focus N` met le focus sur la fenêtre frontmost de l'écran N (ou la première fenêtre tilée si pas de frontmost).
- **FR-014** : `roadie window display <selector>` accepte selector = N (index 1-based) ou `prev`/`next` ou nom (si configuré).

#### Recovery branch/débranch

- **FR-015** : à la déconnexion d'un écran, le système doit migrer toutes ses fenêtres vers le primary screen avec leur frame ajustée pour rester dans le visibleFrame primary, en moins de 500 ms.
- **FR-016** : à la reconnexion d'un écran identique (même `displayID` Quartz), le système ne ramène **pas** automatiquement les fenêtres précédemment migrées. L'utilisateur doit redéplacer manuellement.
- **FR-017** : si une fenêtre persistée a un `display_uuid` qui ne correspond à aucun écran connecté au boot, elle est attachée au primary screen avec frame ajustée.

#### Configuration

- **FR-018** : la section `[[displays]]` dans `roadies.toml` accepte les overrides per-display avec match par `match_index`, `match_uuid`, ou `match_name` (au moins un requis). Champs override : `default_strategy`, `gaps_outer`, `gaps_inner`.
- **FR-019** : changement de config `[[displays]]` est pris en compte à `roadie daemon reload` ou au prochain changement de configuration d'écran.

#### Persistance

- **FR-020** : `WindowEntry` dans `state.toml` du desktop est étendu avec un champ `display_uuid` (string optionnel, vide pour mono-écran ou compat) qui mémorise l'écran d'origine de la fenêtre.
- **FR-021** : au boot, restauration des fenêtres : si `display_uuid` correspond à un écran connecté, restaurer là ; sinon, fallback sur primary.

#### Events

- **FR-022** : un event `display_changed` est émis sur le canal events lorsque l'écran actif change (la fenêtre frontmost passe d'un écran à l'autre). Format JSON : `{"event":"display_changed","from":"<index>","to":"<index>","ts":<unix_ms>}`.
- **FR-023** : un event `display_configuration_changed` est émis lorsque la liste des écrans change (branch/débranch/repositionnement). Format : `{"event":"display_configuration_changed","displays":[{...}],"ts":...}`.

#### Robustesse

- **FR-024** : 0 régression mono-écran. La suite de tests SPEC-011 doit passer à 100 % sans modification.
- **FR-025** : les opérations multi-display doivent être thread-safe (les observers AX et notifications NS arrivent sur des threads différents).

### Key Entities

- **Display** : identifiant interne `id` (Int, basé sur Quartz `CGDirectDisplayID`), `index` (Int 1-based), `name` (String, ex: "Built-in Retina Display"), `uuid` (String, persistent), `frame` (CGRect en coords globales), `visibleFrame` (CGRect en coords globales — exclut menu bar et dock), `isMain` (Bool), `isActive` (Bool — contient la fenêtre frontmost), `tilerStrategy` (Strategy), `gapsOuter` (Int), `gapsInner` (Int).
- **DisplayRegistry** : actor qui maintient la liste des écrans connectés, leur arbre de tiling, et l'écran actif. Observe les changements de configuration d'écran.
- **WindowEntry** (étendu) : ajout du champ `displayUUID: String?` qui mémorise l'écran d'origine.
- **Event** : nouveaux types `display_changed` et `display_configuration_changed`.

## Success Criteria *(mandatory)*

### Mesurables

- **SC-001** : sur 2 écrans, le tiling fonctionne indépendamment par écran — vérifiable par un test E2E qui ouvre 2 fenêtres sur chaque écran et vérifie que `roadie windows.list` montre 4 fenêtres avec frames respectant les visibleFrames de leurs écrans respectifs.
- **SC-002** : `roadie window display 2` déplace une fenêtre tilée du primary vers l'écran 2 en moins de 200 ms p95.
- **SC-003** : déconnexion d'un écran → migration de ses fenêtres vers le primary en moins de 500 ms.
- **SC-004** : 0 régression mono-écran — la suite de tests SPEC-011 passe à 100 % sans modification.
- **SC-005** : `roadie display list` retourne le bon nombre d'écrans dans 100 % des cas, vérifié sur configurations 1, 2, 3 écrans.
- **SC-006** : 0 fenêtre fantôme après branch/débranch — après 10 cycles connect/disconnect, le nombre de fenêtres on-screen est stable.
- **SC-007** : 0 dépendance privée nouvelle — aucun import de SkyLight/CGS au-delà de ce qui existe déjà dans SPEC-011.

### Qualitatifs

- **SC-008** : aucune action utilisateur (modification SIP, scripting addition) n'est requise pour activer le multi-display.
- **SC-009** : sur multi-écran, l'utilisateur lambda voit chaque écran tilé proprement sans toucher à `roadies.toml`. Configuration par défaut suffisante.
- **SC-010** : la documentation utilisateur (README) explique le multi-display en moins de 200 mots.

## Assumptions

- Les écrans physiques sont énumérés via `NSScreen.screens`, qui inclut tous les écrans actifs (pas les écrans en veille).
- Le primary screen (`NSScreen.screens[0]`) est stable pendant la durée d'une session sauf changement explicite par l'utilisateur dans Réglages Système.
- L'option macOS « Les écrans utilisent des Spaces séparés » peut être active OU inactive ; SPEC-012 fonctionne dans les deux cas car roadie n'observe plus les Mac Spaces (cf. SPEC-011 pivot AeroSpace).
- Si Stage Manager Apple natif est actif, son comportement peut interférer avec le tiling roadie. Recommandation : désactiver Stage Manager Apple.
- Pas de support des écrans miroirs (`isMirrored`) : ils sont traités comme un seul écran logique.

## Out of Scope

- **Un desktop différent par écran simultanément** : ex desktop A sur écran 1 + desktop B sur écran 2 en parallèle. Reporté en V4. SPEC-012 garde un desktop global qui se distribue sur tous les écrans connectés.
- **Resize collaboratif inter-écrans** : redimensionner une fenêtre qui dépasse d'un écran à l'autre. Marginal, hors scope.
- **AirPlay / Sidecar** : écrans virtuels via réseau. Hors scope (peuvent fonctionner en pratique si NSScreen les expose, mais non garanti).
- **Mirroring d'écran** : pas de gestion spécifique ; les écrans miroirs sont traités comme un seul.
- **Animation transition entre écrans** : la bascule est instantanée par design (alignée avec SPEC-011).

## Research Findings

### Validation pattern multi-display

- **AeroSpace** documente explicitement le multi-display : un workspace est rattaché à un monitor (`assigned_monitor`), et chaque monitor montre exactement un workspace. Ils notent les limitations natives macOS multi-display (option « Displays have separate Spaces ») mais leur architecture (un seul Mac Space natif, plusieurs workspaces virtuels) contourne le problème.
- **yabai** gère le multi-display avec un space par display ; nécessite SIP partial off pour les opérations cross-display. Notre approche (SPEC-011 + SPEC-012) reste sans SIP off.
- **Hammerspoon / Phoenix** : APIs `hs.screen` / `Screen` exposent NSScreen avec methodes `frame`, `visibleFrame`, `name`. Pattern stable depuis macOS 10.7.

### Red flags

- **Performance avec 5+ écrans** : non testé. Performance théorique linéaire en nombre d'écrans. Cap raisonnable à 4 écrans pour V3, à étendre si demandé.
- **Écrans 8K et au-delà** : `frame` reste en points logiques, pas de problème spécifique. Tester si user feedback.
- **Perte de mappping après débranchement long** : si l'utilisateur débranche pendant des heures, le `displayID` peut changer à la reconnexion (rare, mais documenté). L'approche conservative (pas de restauration auto) évite les positionnements incorrects.
