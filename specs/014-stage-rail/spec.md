# Feature Specification: Stage Rail UI

**Feature Branch**: `014-stage-rail`
**Status**: Draft
**Created**: 2026-05-02
**Dependencies**: SPEC-002 (Stage Manager), SPEC-011 (Virtual Desktops), SPEC-012 (Multi-display)

## Vision

Reprendre l'interface visuelle du **Stage Rail** historique du projet (cf `legacy yabai_stage_rail.swift` et `Sources/roadie/RailUI/RailWindow.swift` du repo `39.roadies.off`) pour exposer le système de stages de roadie de manière directement manipulable à la souris, et reproduire le geste *Apple-Stage-Manager-like* du « click sur le wallpaper qui transforme la collection active en une stage rangée dans le rail ».

L'objectif n'est pas une refonte du fonctionnement des stages (déjà couvert par SPEC-002 + SPEC-011), mais d'apporter une couche **UI dédiée** aux interactions courantes : voir l'état des stages, basculer, déplacer une fenêtre d'une stage à l'autre, créer une nouvelle stage par geste naturel.

## Principes architecturaux non-négociables

1. **Process séparé sans permission système.** Le rail est un binaire `roadie-rail` lancé optionnellement par l'utilisateur (LaunchAgent ou commande). Il **ne demande aucune permission** dans Réglages Système → Confidentialité (ni Accessibility, ni Input Monitoring, ni Screen Recording). Il ne lit AUCUNE API privée. Toutes les opérations passant par le système (lecture AX, capture screen, tilage) sont **déléguées au daemon `roadied`** via le socket Unix existant `~/.roadies/daemon.sock`.

2. **Daemon = single source of truth.** Le rail ne duplique jamais l'état des stages, des fenêtres, ni des desktops. Il interroge `roadied` à la demande et s'abonne à `roadie events --follow` pour les changements en push. Si le daemon est down, le rail affiche un état dégradé visuel ("daemon offline") et ne plante pas.

3. **Daemon étendu pour Screen Recording.** La capture des vraies vignettes de fenêtres (ScreenCaptureKit) impose la permission Screen Recording **côté daemon** (en plus de l'Accessibility actuelle). Le daemon expose une commande IPC `roadie window thumbnail <wid>` qui retourne les bytes PNG de la dernière vignette connue. Le rail consomme ces bytes et les affiche.

4. **Compartimentation runtime.** Le rail est strictement opt-in : si l'utilisateur ne le lance pas, le daemon et le tiling fonctionnent à 100 % comme avant (SPEC-002 + SPEC-011 + SPEC-012). Le retrait du binaire ramène l'expérience à exactement l'état pré-014.

5. **Mono-display d'abord, multi-display d'emblée.** L'archi du rail prévoit un panel par écran connecté (mode `per_display` cohérent avec la config `[desktops] mode = "per_display"` introduite par SPEC-013). Mais la livraison V1 peut commencer par mono-display si la couverture multi-display de SPEC-012 n'est pas encore stabilisée.

## User Scenarios & Testing

### User Story 1 — Voir d'un coup d'œil les stages du desktop courant (P1)

**As a** utilisateur roadie qui a configuré plusieurs stages dans son desktop courant,
**I want** révéler en passant la souris sur l'edge gauche de l'écran un panneau qui liste mes stages avec leurs fenêtres,
**So that** je sache instantanément quels groupes de fenêtres existent sans devoir tester `roadie stage list` en CLI.

**Acceptance scenarios** :
1. Souris approchée à moins de 8 px du bord gauche de l'écran → un panneau de ~408 px de large apparaît en fade-in à 200 ms, montrant la liste verticale des stages du desktop courant.
2. Le panneau a un look distinct (fond sombre semi-transparent avec effet flou natif), un header "Stages" et un hint "Hover left edge. Click to switch • Drag to move."
3. Chaque stage est rendue comme une **carte** : badge avec son ID (1, 2, …), nom de stage, sous-titre "N windows", indicateur visuel (point coloré) si c'est la stage active.
4. Si aucune stage n'existe encore, un message d'état vide invite à en créer une.
5. La souris sort du panneau et de la zone d'edge → fade-out 200 ms et le panneau disparaît.

### User Story 2 — Basculer de stage par click direct (P1)

**As a** utilisateur du rail,
**I want** cliquer sur une carte de stage non-active pour basculer dessus,
**So that** je n'aie pas besoin d'utiliser un raccourci clavier (option ⌥1, ⌥2, …) à chaque fois.

**Acceptance scenarios** :
1. Click gauche sur une carte non-active → le rail demande au daemon `roadie stage <id>` (la stage devient active dans moins de 200 ms, en accord avec la perf déjà tenue par SPEC-002).
2. La carte cliquée passe en état "active" visuellement (bordure changée, point indicateur vert), les anciennes cartes redeviennent "inactive".
3. Click sur la carte déjà active → no-op silencieux (pas de re-trigger inutile).

### User Story 3 — Déplacer une fenêtre d'une stage à une autre par drag-and-drop (P1)

**As a** utilisateur du rail,
**I want** glisser la vignette d'une fenêtre depuis sa carte d'origine vers la carte d'une autre stage,
**So that** je puisse réorganiser mes groupes sans devoir focuser la fenêtre puis taper `⌥⇧N`.

**Acceptance scenarios** :
1. Mouse-down sur une vignette de fenêtre dans une carte → drag session démarre (image de la vignette suit le curseur, sans flash visuel).
2. Drop sur une autre carte de stage → le rail demande au daemon `roadie stage assign <wid> <target_stage>`.
3. La vignette disparaît de la carte source et apparaît dans la carte cible. Le rail rafraîchit son état dans la seconde.
4. Drop hors de toute carte → cancel sans changement.

### User Story 4 — Créer une stage par click sur le wallpaper (P1)

**As a** utilisateur de roadie qui travaille avec un ensemble de fenêtres tilées sur son desktop courant,
**I want** cliquer sur le bureau (le wallpaper) pour transformer cet ensemble en une nouvelle stage qui se range dans le rail,
**So that** je libère mon espace de travail tout en préservant ma collection courante de fenêtres pour y revenir plus tard.

C'est le **geste central** que la SPEC-013 ajoute : équivalent du comportement Stage Manager natif d'Apple, transposé au tiling roadie.

**Acceptance scenarios** :
1. L'utilisateur a 4 fenêtres tilées (BSP) visibles sur son desktop courant. Il clique sur le wallpaper (zone du bureau hors de toute fenêtre).
2. Le daemon détecte le click, snapshot la collection des fenêtres tilées du desktop courant (et seulement les tilées — les floating sont ignorées), crée une nouvelle stage, et minimise les fenêtres dans cette stage.
3. Le rail (s'il est ouvert) affiche immédiatement la nouvelle carte de stage avec les vignettes des fenêtres rangées.
4. Le desktop courant devient vide (= aucune fenêtre tilée visible). L'utilisateur peut ouvrir une nouvelle app pour bâtir une nouvelle collection.
5. Si le rail n'est pas ouvert (pas lancé), le geste ne fait rien (no-op). L'utilisateur doit avoir lancé `roadie-rail` pour bénéficier du comportement.

### User Story 5 — Renommer / supprimer une stage / ajouter la fenêtre frontmost (P2)

**As a** utilisateur du rail,
**I want** un menu contextuel sur clic-droit d'une carte avec les actions "Rename stage…", "Add focused window", "Delete stage",
**So that** je puisse gérer le cycle de vie de mes stages sans CLI.

**Acceptance scenarios** :
1. Clic droit sur une carte → menu contextuel apparaît avec 3 entrées + séparateurs.
2. "Rename stage…" → un champ de saisie inline ou une mini-modale demande le nouveau nom (max 32 caractères), validation par Entrée → daemon appelé.
3. "Add focused window" → le daemon assigne la fenêtre actuellement focused à cette stage.
4. "Delete stage" → confirmation visuelle (clic-pour-confirmer ou prompt minimal), puis suppression daemon-side. Si la stage active est supprimée, le rail bascule sur la stage 1 par défaut (comportement SPEC-002).

### User Story 6 — Récupérer l'espace horizontal pour le contenu (P2)

**As a** utilisateur qui veut un rail toujours-visible OU un rail apparaissant en hover sans recouvrir mon contenu,
**I want** une option de configuration `[fx.rail] reclaim_horizontal_space = true` qui force le tiler à réduire le workArea pendant que le rail est visible (pour que mes fenêtres tilées s'écartent et libèrent la place),
**So that** je puisse choisir entre overlay (rail flotte par-dessus) et reclaim (rail prend de la place dur).

**Acceptance scenarios** :
1. `reclaim_horizontal_space = false` (default) : le rail apparaît en surimpression. Les fenêtres tilées dessous gardent leur frame, le rail couvre simplement les ~408 px d'edge gauche pendant qu'il est visible.
2. `reclaim_horizontal_space = true` : à l'apparition du rail, le daemon retiles avec un workArea réduit (`x: rail_width, width: screen_width - rail_width`). Les fenêtres se réduisent doucement (animation respectant les params globaux). À la disparition du rail, le daemon retiles avec le workArea initial.
3. Le retiling déclenché par le rail respecte la latence cible 200 ms de SPEC-002 (pas de jank visible).

### User Story 7 — Multi-display : un rail par écran (P2)

**As a** utilisateur multi-display,
**I want** un rail séparé sur chaque écran connecté, chacun montrant les stages du desktop courant **de cet écran** (avec mode `per_display`),
**So that** je puisse manipuler indépendamment les stages sur chaque écran.

**Acceptance scenarios** :
1. Avec `[desktops] mode = "per_display"` (cf SPEC-013) et 2 écrans : 2 rails, un sur l'edge gauche de chaque écran, indépendants.
2. Hover sur l'edge gauche de l'écran 1 ouvre uniquement le rail de l'écran 1 (pas de cross-talk).
3. Click wallpaper sur l'écran 2 crée une stage qui apparaît dans le rail de l'écran 2 (pas de l'écran 1).
4. Avec `[desktops] mode = "global"` (un seul desktop logique sur tous les écrans) : un seul rail, sur l'écran principal.

## Functional Requirements

### Lifecycle & Architecture
- **FR-001** : le binaire `roadie-rail` est livré dans le même bundle/release que `roadie` et `roadied`. Il est **opt-in** : aucun lancement automatique, l'utilisateur le démarre manuellement ou via un LaunchAgent qu'il configure lui-même (un exemple est fourni dans `quickstart.md`).
- **FR-002** : `roadie-rail` ne demande aucune permission système au runtime. Il fait UN appel socket de healthcheck au daemon au démarrage et exit avec un message d'erreur clair si le socket est introuvable.
- **FR-003** : `roadie-rail` est mono-instance par utilisateur. Un second lancement détecte l'instance existante (via fichier PID-lock dans `~/.roadies/`) et exit silencieusement.

### Communication daemon
- **FR-004** : tout l'état affiché par le rail provient du daemon via les commandes IPC existantes (`stage list`, `desktop current`, `window list`) et d'une nouvelle commande `roadie window thumbnail <wid>` (PNG bytes).
- **FR-005** : le rail s'abonne à `roadie events --follow` pour recevoir en push : `stage_changed`, `desktop_changed`, `window_assigned`, `window_unassigned`, `window_created`, `window_destroyed`. Pas de polling périodique pour ces events.
- **FR-006** : si la connexion socket est perdue (daemon crash, restart), le rail tente une reconnexion exponentielle (100 ms, 500 ms, 2 s, plafonnée à 5 s). Pendant la déconnexion, le rail affiche un état dégradé "daemon offline".

### Capture des vignettes (ScreenCaptureKit, côté daemon)
- **FR-007** : le daemon expose une commande IPC `roadie window thumbnail <wid>` qui retourne les bytes PNG de la dernière vignette de la fenêtre. Si la fenêtre n'est plus visible (minimisée, hors-écran), retourne la dernière vignette connue (cache LRU en mémoire daemon).
- **FR-008** : la capture utilise ScreenCaptureKit (macOS 14+). Le daemon refresh les vignettes des fenêtres visibles toutes les 2 secondes max (pas de pression CPU continue) et à la demande quand le rail observe une fenêtre.
- **FR-009** : la résolution des vignettes est plafonnée à 320×200 px max (assez pour rendu chip 64×40 dans le rail) et ré-échantillonnée si la fenêtre source est plus grande.
- **FR-010** : si la permission Screen Recording n'est pas accordée, le daemon retourne une vignette de fallback (icône d'app NSWorkspace) avec un flag `degraded=true` dans la réponse. Le rail affiche les icônes d'app sans erreur visuelle bloquante.

### UI rail — apparition / disparition
- **FR-011** : le rail détecte l'approche de la souris sur l'edge gauche de chaque écran connecté via polling de `NSEvent.mouseLocation` à 80 ms (12 Hz). Pas d'utilisation de `NSEvent.addGlobalMonitorForEvents` (qui exigerait Input Monitoring permission).
- **FR-012** : le panneau apparaît en fade-in 200 ms quand la souris pénètre la zone edge (8 px de large × hauteur de l'écran).
- **FR-013** : le panneau disparaît en fade-out 200 ms quand la souris quitte simultanément la zone edge ET la zone du panel (debounce 100 ms pour éviter les clignotements).
- **FR-014** : le panneau utilise `NSPanel` non-activating (ne vole pas le focus clavier) avec `level = .statusBar` (au-dessus des fenêtres standard mais sous les modales système).

### UI rail — contenu et interactions
- **FR-015** : le panneau affiche les **stages du desktop courant uniquement**. Pas de section "tous les desktops". Le scope se met à jour automatiquement sur l'event `desktop_changed`.
- **FR-016** : chaque stage est rendue comme une **carte SwiftUI** avec : badge ID (visible et lisible), nom de stage (police système ~14 pt), sous-titre "N windows • active" si active, indicateur visuel d'état actif distinct.
- **FR-017** : chaque carte contient une row horizontale de vignettes de fenêtres (max 8 visibles + indicateur "+N" si plus). Chaque vignette est draggable (NSDraggingSession) et clic-droit sur une vignette propose "Remove from stage".
- **FR-018** : click gauche sur une carte non-active → bascule sur cette stage via daemon. Click sur la carte active → no-op.
- **FR-019** : clic-droit sur une carte → menu contextuel avec 3 entrées : Rename, Add focused window, Delete.
- **FR-020** : drop d'une vignette de fenêtre depuis une carte source vers une carte cible → daemon assign window vers stage cible.

### Geste click-on-wallpaper (côté daemon, lié au rail)
- **FR-021** : le daemon détecte les clicks souris hors de toute fenêtre tracked et hors du rail (= "click sur le wallpaper du desktop"). Détection via `kAXMouseDownEvent` AX (déjà disponible via les permissions Accessibility actuelles, sans Input Monitoring additionnel).
- **FR-022** : à la détection d'un click wallpaper, **et seulement si le rail est lancé** (présence du PID-lock), le daemon : crée une nouvelle stage, lui assigne TOUTES les fenêtres tilées du desktop courant (les floating sont laissées intactes), bascule sur cette nouvelle stage virtuelle vide.
- **FR-023** : la nouvelle stage hérite du nom auto-généré "Stage N" où N est l'ID croissant. L'utilisateur peut la renommer immédiatement via le rail.
- **FR-024** : le geste est **désactivable** via `[fx.rail] wallpaper_click_to_stage = false` dans la config TOML (default `true`). Si désactivé, click wallpaper redevient un no-op.

### Reclaim horizontal space
- **FR-025** : option TOML `[fx.rail] reclaim_horizontal_space` (bool, default `false`) contrôle si le tiler réduit le workArea quand le rail est visible.
- **FR-026** : si `true`, à l'apparition du rail le daemon ajuste le workArea du primary screen (ou de l'écran qui contient le rail) à `(rail_width, 0, screen_width - rail_width, screen_height)` puis re-appelle `applyLayout`. À la disparition, restoration immédiate.
- **FR-027** : pendant l'animation de fade-in/fade-out du rail, le retiling se déclenche **une fois** au début de la transition, pas continuellement (pour éviter les saccades).

### Multi-display
- **FR-028** : avec `[desktops] mode = "per_display"`, le rail instancie un panel par écran connecté. Chaque panel observe son propre edge et affiche les stages du desktop courant **de son écran**.
- **FR-029** : avec `[desktops] mode = "global"`, le rail instancie un panel sur l'écran principal uniquement.
- **FR-030** : à un changement de configuration d'écran (`didChangeScreenParametersNotification`), le rail recrée ses panels en conséquence sans nécessiter de redémarrage.

### Configuration et persistence
- **FR-031** : la config du rail vit dans la section `[fx.rail]` du fichier `~/.config/roadies/roadies.toml`. Si la section est absente, les valeurs par défaut documentées ci-dessous sont utilisées (rail fonctionnel out-of-the-box). Si une clé individuelle est absente, sa valeur par défaut est appliquée — pas d'erreur de parsing :
  ```toml
  [fx.rail]
  enabled = true                       # contrôle aussi le wallpaper_click_to_stage
  reclaim_horizontal_space = false
  wallpaper_click_to_stage = true
  panel_width = 408
  edge_width = 8
  fade_duration_ms = 200
  ```
- **FR-032** : le rail recharge sa config sur l'event `config_reloaded` (déjà émis par le daemon sur `roadie daemon reload`).

## Success Criteria

- **SC-001** : sur un poste avec 4 stages et 12 fenêtres réparties, le hover edge gauche fait apparaître le rail en moins de **300 ms** end-to-end (détection souris → render complet avec vignettes).
- **SC-002** : un click sur une carte de stage déclenche le switch en moins de **200 ms** (cohérent avec SPEC-002 SC-006).
- **SC-003** : un drag-drop d'une vignette d'une carte à une autre déplace la fenêtre dans le bon stage en moins de **300 ms** après le drop.
- **SC-004** : sur 8 heures d'usage, le binaire `roadie-rail` consomme moins de **30 MB de RSS** et **<1 % CPU moyen** (le daemon supporte le coût d'observation, pas le rail).
- **SC-005** : si l'utilisateur retire le binaire `roadie-rail` du système, le daemon `roadied` continue de fonctionner identique à pré-014, sans warning ni dégradation. Le geste click-wallpaper devient un no-op silencieux.
- **SC-006** : avec `reclaim_horizontal_space = true`, l'écart entre l'animation du rail (fade-in 200 ms) et le retiling est imperceptible à l'œil (pas de jank > 1 frame à 60 Hz, soit 16 ms).
- **SC-007** : si la permission Screen Recording n'est pas accordée au daemon, le rail tombe gracieusement sur les icônes d'app (résolues via `NSWorkspace.shared.icon(forFile: app.bundleURL.path)`, ré-échantillonnées à 128×128 px, encodées PNG) et reste pleinement utilisable (les actions click/drag fonctionnent).
- **SC-008** : zéro régression sur les SPECs précédentes : la suite de tests SPEC-002, SPEC-011, SPEC-012 et SPEC-013 doit passer à 100 % avec et sans `roadie-rail` lancé.
- **SC-009** : multi-display : 2 écrans connectés, hover edge gauche de chacun ouvre indépendamment le rail correspondant en moins de 300 ms, sans cross-talk visuel.
- **SC-010** : le geste click-on-wallpaper crée la stage et migre les fenêtres tilées en moins de **400 ms** après le click (incluant la détection AX, le snapshot des fenêtres, l'écriture state.toml, et le rafraîchissement du rail).

## Key Entities

- **`StageRailPanel`** : un panel `NSPanel` (host SwiftUI) par écran. Contient un `StageStack` SwiftUI et gère les transitions d'apparition.
- **`StageCard`** : vue SwiftUI représentant une stage : badge ID, titre, sous-titre, indicateur actif, drop target, click target, contextual menu.
- **`WindowChip`** : vue SwiftUI représentant une fenêtre dans une carte : vignette ScreenCaptureKit (ou icône d'app en fallback), drag source, contextual remove.
- **`RailIPCClient`** : client socket Unix qui parle au daemon (commandes ponctuelles + abonnement events).
- **`ThumbnailCache`** : cache LRU côté daemon (capacité ~50 vignettes), refresh sur observation par le rail.
- **`WallpaperClickWatcher`** : composant côté daemon qui détecte les clicks AX hors fenêtres tracked et déclenche la création de stage.

## Out of Scope (V1)

- **Animations CSS-style entre stages** : pas de morphing visuel entre deux états de stage (l'animation reste limitée au fade-in/fade-out du panel et à la transition de couleur active/inactive).
- **Personnalisation du look** (thèmes utilisateur, custom CSS) : V1 livre un seul thème natif macOS Tahoe-like, hardcodé.
- **Stages globales cross-desktop** : la spec couvre uniquement les stages du desktop courant. Voir les stages d'un autre desktop demande de switcher d'abord.
- **Customisation de l'edge** : V1 = edge gauche uniquement. Edge droit / haut / bas reportés à V2.
- **Drag fenêtre depuis le bureau vers le rail** : seul le drag chip-à-chip est couvert. Pas de "glisser une fenêtre standard sur le rail pour l'ajouter à une stage".
- **Vignettes live-updating** (vidéo des fenêtres) : V1 = snapshots PNG périodiques (2 s d'écart). Live-streaming reporté.
- **Compatibilité avec un setup sans daemon** : si `roadied` n'est pas lancé, le rail affiche "daemon offline" et n'a aucune fonctionnalité utile.

## Assumptions

- L'utilisateur est sur macOS 14+ (cohérent avec le projet, SwiftUI utilisé).
- L'utilisateur a déjà accordé la permission Accessibility au daemon (prérequis SPEC-002).
- L'utilisateur accepte d'accorder la permission Screen Recording au daemon pour bénéficier des vraies vignettes (sinon fallback icônes d'app).
- L'utilisateur lance lui-même `roadie-rail` ou configure un LaunchAgent — pas de démarrage automatique invasif.

## Research Findings

- **Référence visuelle** : ancien projet `39.roadies.off/yabai_stage_rail.swift` (~1100 LOC AppKit, NSVisualEffectView `.hudWindow`, polling souris 80 ms, fade 200 ms, badge 32×22, cards 16 px corner radius). Look précis détaillé dans `plan.md` et `research.md`.
- **Pattern Apple Stage Manager natif** : geste click-wallpaper = comportement natif macOS Sonoma+. La spec reproduit ce concept dans le contexte tiling roadie pour cohérence d'expérience utilisateur.
- **Screen Recording permission daemon-side** : pattern standard yabai/AeroSpace pour intégrations vignettes. Pas de risque sécurité supplémentaire significatif (le daemon a déjà l'Accessibility).
- **NSPanel non-activating + level statusBar** : pattern éprouvé pour HUD overlays (Spotlight, Mission Control, Hammerspoon HUDs). Pas de vol de focus clavier.

## Risks & Mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Polling souris 80 ms consomme CPU | Bas (≈0.5 % observé yabai_stage_rail.swift) | Profiler en V1, basculer sur `NSEvent.addGlobalMonitorForEvents` si polling trop coûteux (avec acceptation de la permission Input Monitoring) |
| Permission Screen Recording refusée | Moyen (UX dégradée) | Fallback icônes d'app fonctionnel, pas de blocage. Onboarding clair dans quickstart |
| ScreenCaptureKit lourd sur batterie | Moyen | Refresh thumbnails capé à 0.5 Hz, suspendu si rail fermé depuis > 30 s, cache LRU agressif |
| Le daemon crash → rail orphelin | Bas | Reconnexion exponentielle, état "daemon offline" non bloquant |
| Conflit avec Mission Control / Spotlight (hover edge) | Moyen | Edge sensor à 8 px largeur, `collectionBehavior` excluant les hot corners système |
| Tahoe 26 introduit nouvelle restriction | Élevé (cf ADR-005 osax) | La spec n'utilise QUE des APIs publiques côté rail. Le daemon ScreenCaptureKit est une API publique macOS 14+ documentée. Pas de surface privée. |

## Constitution Check (à valider en plan.md)

- [ ] Article A : pas de mono-fichier > 200 LOC effectives
- [ ] Article B : zéro dépendance non justifiée
- [ ] Article C' : pas de SkyLight write privé (rail = lecture seule via daemon)
- [ ] Article D : pas de `try!`, pas de `print()`, logger structuré
- [ ] Article G : plafond LOC à confirmer (cible 1500 / plafond 2000 pour le binaire rail SwiftUI + extensions daemon)

## Open Questions

(aucune au moment de la rédaction — toutes les ambiguïtés ont été résolues lors de la session interactive du 2026-05-02)
