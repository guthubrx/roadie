# Feature Specification: Roadie Virtual Desktops

**Feature Branch**: `011-virtual-desktops`
**Created**: 2026-05-02
**Status**: Draft
**Dependencies**: SPEC-001 (stage-manager), SPEC-002 (tiler-stage). Remplace **SPEC-003** (multi-desktop, deprecated).
**Input**: Pivot V2 multi-desktop. Le mécanisme initial (1 Roadie Desktop = 1 Mac Space natif, bascule via `CGSManagedDisplaySetCurrentSpace`) est cassé par une régression macOS Tahoe 26 documentée (yabai issue #2656). Pivot vers le pattern AeroSpace : tous les desktops virtuels Roadie vivent dans **un seul** Mac Space natif, la bascule consiste à déplacer offscreen les fenêtres du desktop quitté et à restaurer on-screen celles du desktop d'arrivée.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Bascule instantanée entre desktops virtuels (Priority: P1)

L'utilisateur travaille sur le desktop 1 avec Mail et Slack ouverts. Il appuie sur ⌘+é (AZERTY 2). Roadie cache instantanément Mail et Slack (déplacés hors-écran), restaure les fenêtres du desktop 2 (par exemple Xcode et Terminal) à leurs positions précédentes, et applique le layout du desktop 2. La bascule est perçue comme instantanée (< 200 ms). SketchyBar voit l'event `desktop_changed` et met à jour son indicateur.

**Why this priority** : c'est la fonctionnalité cœur du pivot. Sans elle, il n'y a pas de multi-desktop. Toute la valeur utilisateur passe par cette bascule.

**Independent Test** : avec deux fenêtres Mail+Slack sur desktop 1 et deux Xcode+Terminal sur desktop 2, lancer `roadie desktop focus 2` ; vérifier que Mail+Slack disparaissent visuellement (positions hors-écran observables via `roadie windows.list`), Xcode+Terminal réapparaissent à leurs positions, `roadie desktop current` retourne `2`, l'event `desktop_changed` est émis sur le canal events.

**Acceptance Scenarios** :

1. **Given** desktop 1 actif avec 2 fenêtres aux positions (100,100) et (500,100), desktop 2 actif précédemment avec 2 fenêtres mémorisées aux positions (200,200) et (600,200), **When** l'utilisateur déclenche `roadie desktop focus 2`, **Then** les 2 fenêtres du desktop 1 ont une frame.origin hors de tout `visibleFrame` d'écran, les 2 fenêtres du desktop 2 sont à (200,200) et (600,200), `roadie desktop current` retourne `2`, et un event JSON `{"event":"desktop_changed","from":"1","to":"2"}` est émis sur le canal events en moins de 200 ms.
2. **Given** l'utilisateur est sur desktop 1, **When** il déclenche `roadie desktop focus 1` (le même), **Then** rien ne change visuellement et aucun event `desktop_changed` n'est émis (no-op idempotent).
3. **Given** `back_and_forth = true` et `recent = 3`, l'utilisateur sur desktop 1, **When** `roadie desktop focus 1`, **Then** la bascule s'effectue vers le desktop 3 (back-and-forth).

---

### User Story 2 — Stages préservés à l'identique dans chaque desktop (Priority: P1)

L'utilisateur sur desktop 1 a deux stages (stage A : Mail, stage B : Slack). Il appuie sur ⌥+1 puis ⌥+2 — les stages bascule dans le desktop 1 comme avant le pivot. Il bascule au desktop 2 via ⌘+é, qui a son propre stage 1 (Xcode) et stage 2 (Terminal). Sur desktop 2, ⌥+1/⌥+2 manipulent uniquement les stages de desktop 2, sans interférer avec les stages de desktop 1.

**Why this priority** : la promesse "zéro régression V1" est centrale. Si les stages cassent, c'est une régression majeure inacceptable.

**Independent Test** : créer 2 stages sur desktop 1, basculer au desktop 2, créer 2 stages, basculer entre stages via ⌥+1/⌥+2 ; les commandes ne doivent affecter QUE les stages du desktop courant.

**Acceptance Scenarios** :

1. **Given** desktop 1 a stages [A,B] et desktop 2 a stages [C,D], desktop courant = 1, **When** ⌥+2 est pressé, **Then** stage B devient actif sur desktop 1, stages de desktop 2 inchangés.
2. **Given** desktop courant = 2, **When** `roadie stage list` est exécuté, **Then** seuls les stages [C,D] de desktop 2 sont retournés.

---

### User Story 3 — État persisté par desktop (Priority: P1)

L'utilisateur configure desktop 1 avec un layout BSP et 3 fenêtres positionnées, desktop 2 avec un layout master-stack et 5 fenêtres. Il quitte le daemon (ou redémarre la machine). Au redémarrage, le state de chaque desktop est restauré : positions, layout, stages, assignments fenêtre→stage.

**Why this priority** : le multi-desktop n'a de valeur que si le contexte de travail survit aux redémarrages. C'est ce qui distingue un workspace utile d'un simple toggle visuel.

**Independent Test** : configurer 2 desktops avec contenu distinct, `kill` du daemon puis relance, vérifier que `roadie desktop list` montre les mêmes desktops avec mêmes fenêtres assignées et mêmes layouts.

**Acceptance Scenarios** :

1. **Given** desktop 1 avec layout BSP + 3 fenêtres assignées, desktop 2 avec layout master-stack + 5 fenêtres, **When** le daemon est tué et relancé, **Then** `roadie desktop list` retourne les mêmes 2 desktops avec mêmes counts de fenêtres et mêmes labels, et `roadie desktop focus 1` puis `focus 2` montrent visuellement les fenêtres aux mêmes positions qu'avant l'arrêt.

---

### User Story 4 — Lister, labeliser, sélectionner par nom (Priority: P2)

L'utilisateur veut donner des noms à ses desktops (`code`, `comm`, `web`) et basculer par nom plutôt que par numéro. Il exécute `roadie desktop label code` sur le desktop 3, puis `roadie desktop focus code` qui bascule au desktop 3.

**Why this priority** : améliore l'usabilité et permet d'écrire des scripts résilients aux changements d'ordre des desktops, mais le numéro 1..10 fonctionne sans labels — donc P2.

**Independent Test** : labeliser 2 desktops, basculer par label, vérifier que `roadie desktop list` affiche les labels.

**Acceptance Scenarios** :

1. **Given** desktop courant = 3, **When** `roadie desktop label code` puis `roadie desktop focus code`, **Then** desktop 3 est actif et `roadie desktop list` affiche `3 | code | current=true`.
2. **Given** un label `code` existe, **When** `roadie desktop label ""` est exécuté sur ce desktop, **Then** le label est retiré et `focus code` retourne une erreur "unknown selector".

---

### User Story 5 — Stream d'events pour intégrations externes (Priority: P2)

L'utilisateur a une menu bar custom (SketchyBar, AnyBar, etc.) qui doit refléter le desktop et le stage actifs. Il lance `roadie events --follow` qui streame des JSON-lines `{"event":"desktop_changed",...}` et `{"event":"stage_changed",...}` à chaque transition. Le script `sketchybar --trigger ...` est invoqué à la réception.

**Why this priority** : nécessaire pour les intégrations menu bar mais pas bloquant pour l'usage solo de roadie.

**Independent Test** : lancer `roadie events --follow > /tmp/events.jsonl &`, basculer 3 fois entre desktops, vérifier 3 lignes `desktop_changed` dans le fichier avec les UUIDs cohérents.

**Acceptance Scenarios** :

1. **Given** un client `roadie events --follow` connecté, **When** une bascule de desktop a lieu, **Then** une ligne JSON `{"event":"desktop_changed","from":"<from>","to":"<to>","ts":<unix_ms>}` est écrite sur stdout du client en moins de 50 ms après la bascule.

---

### User Story 6 — Migration transparente depuis V1 (Priority: P2)

Un utilisateur V1 (sans multi-desktop) lance la nouvelle version. Au premier boot, ses stages V1 et fenêtres existantes sont mappés au desktop virtuel 1. Le comportement perçu est identique à V1 — aucune fenêtre ne disparaît, les ⌥+1/⌥+2 fonctionnent comme avant. L'utilisateur peut activer les desktops 2..N quand il le souhaite.

**Why this priority** : critique pour l'adoption mais réversible (peut être différée d'1 release).

**Independent Test** : prendre un state V1 existant, lancer la nouvelle version, observer que toutes les fenêtres apparaissent sur desktop 1, stages préservés, raccourcis stages fonctionnels.

**Acceptance Scenarios** :

1. **Given** state V1 dans `~/.config/roadies/stages/` avec 2 stages et 5 fenêtres, **When** la nouvelle version démarre pour la première fois, **Then** `roadie desktop list` retourne 1 desktop "1" contenant les 5 fenêtres et les 2 stages, `roadie stage list` retourne les 2 stages identiques, ⌥+1/⌥+2 basculent comme avant.

---

### User Story 7 — Désactivation multi-desktop pour utilisateurs minimalistes (Priority: P3)

Un utilisateur préfère un seul "desktop" (comportement V1 strict). Il pose `desktops.enabled = false` dans `roadies.toml`. Roadie ignore alors les commandes `desktop.*`, retourne une erreur `multi_desktop disabled` proprement, et se comporte exactement comme V1.

**Why this priority** : flag d'opt-out de sûreté pour les utilisateurs qui ne veulent pas du pivot. Pas critique car le default est `enabled=true`.

**Independent Test** : poser `enabled=false` dans la config, redémarrer le daemon, vérifier que `roadie desktop focus 2` retourne une erreur claire et que ⌘+é ne déclenche aucune bascule.

**Acceptance Scenarios** :

1. **Given** `[desktops] enabled = false`, **When** `roadie desktop focus 2`, **Then** la commande retourne exit code != 0 avec message `multi_desktop disabled, set enabled=true in roadies.toml`.

---

### Edge Cases

- **Fenêtre fermée pendant qu'elle est offscreen** (sur un desktop non-courant) : la fenêtre disparaît du registry du desktop concerné au prochain refresh. Pas de fenêtre fantôme persistée.
- **Nouvelle fenêtre créée pendant que le focus est sur desktop N** : la nouvelle fenêtre est assignée automatiquement au desktop courant N et au stage par défaut de ce desktop.
- **Fenêtre déplacée manuellement par l'utilisateur** (drag) sur un desktop pendant qu'elle est on-screen : la nouvelle position est mémorisée comme position attendue pour cette fenêtre sur ce desktop, et restaurée aux bascules suivantes.
- **Application qui force le redessin de ses fenêtres** (ex : Mission Control native, Stage Manager Apple si activé) : roadie ne lutte pas. Si une fenêtre offscreen est ramenée on-screen par une force externe, roadie l'enregistre comme "déplacée" et la considère désormais sur le desktop courant.
- **Display unplug / replug** (V3 multi-display) : hors scope V2. En V2 mono-display, si l'utilisateur change de display, le state est conservé mais peut nécessiter un reset visuel.
- **Sur Mac Space natif différent (l'utilisateur a Ctrl+→ macOS)** : roadie ignore. Les fenêtres roadie suivent l'utilisateur (toutes assignées au Mac Space où elles ont été créées). Recommandation utilisateur : désactiver "Displays have separate Spaces" et utiliser un seul Mac Space natif.
- **Crash du daemon avec fenêtres offscreen** : au prochain démarrage, le daemon restaure les positions on-screen pour le desktop courant. Si l'état persisté est incohérent, le daemon affiche un warning et restaure tout sur le desktop 1.
- **Fenêtre fullscreen ou minimisée** : roadie ne touche pas aux fenêtres en fullscreen natif macOS (qui sont sur leur propre Mac Space). Les fenêtres minimisées restent dans leur état, leur "position offscreen" est sans effet visuel mais préservée pour la restauration.
- **Bascule rapide ⌘+& puis ⌘+é en moins de 100 ms** : les bascules sont sérialisées via une queue ; la dernière commande gagne, les intermédiaires sont annulées sans laisser de fenêtres offscreen.

## Requirements *(mandatory)*

### Functional Requirements

#### Bascule et état

- **FR-001** : le système doit permettre la bascule entre exactement N desktops virtuels où `1 ≤ N ≤ 16`, configurable via `[desktops] count` (défaut 10).
- **FR-002** : la bascule de desktop A → desktop B doit déplacer toutes les fenêtres assignées à A à des positions hors de tout `visibleFrame` d'écran connecté (ex : `(-30000, -30000)`), et restaurer les fenêtres assignées à B à leur position mémorisée.
- **FR-003** : la bascule doit être perceptiblement instantanée — temps mesuré entre l'invocation et la dernière fenêtre repositionnée < 200 ms pour ≤ 10 fenêtres au total sur les deux desktops.
- **FR-004** : aucun appel SkyLight/CGS ne doit être fait pour la bascule de desktop. Aucune scripting addition macOS ne doit être requise. Aucune modification de SIP ne doit être requise.
- **FR-005** : le système doit conserver, pour chaque fenêtre, sa **position attendue** (frame.origin) sur son desktop. Cette position est mise à jour à chaque fois que la fenêtre est on-screen et que l'utilisateur la déplace.

#### Idempotence et back-and-forth

- **FR-006** : `desktop.focus N` où N est déjà courant doit être un no-op (aucun déplacement de fenêtre, aucun event émis), sauf si `back_and_forth = true` auquel cas la bascule s'effectue vers le desktop `recent`.
- **FR-007** : le système doit mémoriser le `recent_desktop_id` (le dernier desktop quitté), accessible via `roadie desktop back`.

#### Stages dans desktops

- **FR-008** : chaque desktop possède son propre ensemble de stages indépendant des autres desktops. Le passage d'un desktop à l'autre charge les stages du desktop d'arrivée et masque ceux du desktop quitté.
- **FR-009** : les commandes `roadie stage list/focus/create/destroy` doivent opérer **uniquement** sur les stages du desktop courant.
- **FR-010** : les raccourcis BTT existants (⌥+1, ⌥+2, etc.) doivent continuer à manipuler les stages du desktop courant — aucun breaking change BTT.

#### Persistance

- **FR-011** : l'état complet de chaque desktop (liste de fenêtres, positions, stages, layout, gaps, label) doit être persisté sur disque dans `~/.config/roadies/desktops/<id>/`, écrit immédiatement après chaque bascule ou modification structurelle.
- **FR-012** : au démarrage du daemon, l'état persisté de chaque desktop doit être chargé avant la première commande utilisateur, et le desktop précédemment courant (ou `default_focus`) doit être affiché.
- **FR-013** : si l'état persisté est corrompu pour un desktop, le système doit logger un warning et initialiser un état vierge pour ce desktop, sans bloquer le boot.

#### CLI et events

- **FR-014** : la CLI doit fournir `roadie desktop list/focus/current/label/back` avec sémantique stable.
- **FR-015** : `roadie desktop list` doit retourner pour chaque desktop : id (1..N), label optionnel, count fenêtres, count stages, current bool, recent bool.
- **FR-016** : `roadie events --follow` doit streamer en JSON-lines tout event `desktop_changed` et `stage_changed` avec timestamp Unix ms, dans un délai inférieur à 50 ms après l'event interne.
- **FR-017** : la CLI doit retourner immédiatement (sans bloquer) — aucune commande ne doit pendre plus de 1 s en attente.

#### Configuration

- **FR-018** : la configuration `[desktops]` dans `roadies.toml` doit supporter au minimum : `enabled` (bool, défaut true), `count` (int, défaut 10), `default_focus` (int, défaut 1), `back_and_forth` (bool, défaut true).
- **FR-019** : un changement de configuration `enabled` doit être pris en compte au prochain démarrage du daemon (pas à chaud).
- **FR-020** : si `enabled = false`, toutes les commandes `desktop.*` doivent retourner une erreur claire `multi_desktop disabled` ; les commandes `stage.*` continuent de fonctionner sur l'unique desktop par défaut (id 1).

#### Migration

- **FR-021** : au premier démarrage de la nouvelle version sur une installation V1 existante, l'état des stages V1 (`~/.config/roadies/stages/`) doit être mappé vers `desktop_id = 1`, et les fenêtres existantes assignées à ce desktop, sans intervention utilisateur.
- **FR-022** : la SPEC-003 (multi-desktop V2 ancien, indexé par UUID Mac Space) doit être marquée DEPRECATED dans son spec.md ; aucune trace fonctionnelle ne doit subsister dans la configuration ou le state au démarrage de la nouvelle version (les fichiers `~/.config/roadies/desktops/<uuid>/` issus de SPEC-003 doivent être migrés vers le nouveau format `~/.config/roadies/desktops/<id>/` ou archivés sans casser le boot).

#### Robustesse

- **FR-023** : le système doit refuser une bascule vers un desktop_id hors range `[1..count]` avec une erreur `unknown desktop selector`.
- **FR-024** : si une fenêtre persistée n'existe plus côté macOS (app fermée), le système doit l'ignorer silencieusement à la restauration sans bloquer la bascule.
- **FR-025** : les bascules concurrentes (deux invocations en moins de 50 ms) doivent être sérialisées sur une queue ; la dernière requête gagne, les intermédiaires sont annulées.

### Key Entities

- **RoadieDesktop** : identifiant entier `1..count`, label optionnel (string ≤ 32 chars, alphanumérique + `-_`), liste de fenêtres assignées, layout (BSP / master-stack / floating), gaps (outer/inner), stage actif, liste de stages.
- **Window** : identifiant `CGWindowID` (UInt32), bundle ID, titre, frame mémorisée (position attendue lorsque on-screen), `desktop_id` d'appartenance, `stage_id` d'appartenance.
- **Stage** : identifiant local au desktop (1..M), liste de fenêtres assignées, layout, label optionnel.
- **Event** (canal observable) : type (`desktop_changed`, `stage_changed`), `from`, `to`, timestamp Unix ms.

## Success Criteria *(mandatory)*

### Mesurables

- **SC-001** : la bascule entre 2 desktops avec 10 fenêtres au total est perçue comme instantanée — délai mesuré entre l'invocation de la commande et le dernier repaint des fenêtres < 200 ms en p95 sur un MacBook Pro 2021 ou plus récent.
- **SC-002** : 0 fenêtre fantôme — après 100 bascules consécutives, le nombre de fenêtres on-screen correspond exactement au nombre attendu pour le desktop courant (vérifiable via `roadie windows.list`).
- **SC-003** : 0 régression sur les stages V1 — un test E2E exécute la suite stage V1 actuelle et passe à 100 % sur la nouvelle version.
- **SC-004** : 0 perte de fenêtre à la migration — un utilisateur V1 avec N fenêtres voit ces N fenêtres au premier boot V2 sans intervention manuelle.
- **SC-005** : 0 appel SkyLight/CGS pour la bascule — une grep du code de bascule de desktop ne doit pas matcher `CGS` / `SLS` / `SkyLight` (validation statique du code).
- **SC-006** : la persistance survit au redémarrage daemon — après `kill` + relance, 100 % des positions de fenêtres et 100 % des labels de desktops sont restaurés à l'identique.
- **SC-007** : le canal events publie une transition en moins de 50 ms après l'event interne, mesuré entre `roadie desktop focus N` retour et la ligne JSON sur stdout du subscriber.

### Qualitatifs

- **SC-008** : aucune action utilisateur (modification SIP, signature de binaire tiers, scripting addition à installer) n'est requise pour activer les desktops virtuels.
- **SC-009** : un utilisateur V1 qui démarre la nouvelle version sans rien changer à sa config retrouve son environnement de travail à l'identique en moins de 5 secondes (boot daemon + restauration desktop 1).
- **SC-010** : la documentation utilisateur (README ou docs) explique le pivot et la recommandation "désactiver Displays have separate Spaces" en moins de 200 mots.

## Assumptions

- L'utilisateur a un seul Mac Space natif actif, ou accepte que roadie ignore les autres Mac Spaces (recommandation : désactiver "Displays have separate Spaces" dans Réglages Système).
- L'utilisateur a un seul écran (multi-display reporté V3).
- Le mécanisme `setLeafVisible` (déjà utilisé pour les stages) est suffisant pour cacher/montrer les fenêtres ; aucune nouvelle API privée macOS n'est introduite.
- Les fenêtres macOS qui n'exposent pas leur frame via Accessibility (cas marginal des apps utilisant uniquement OpenGL/Metal en plein écran custom) sont hors scope — comportement non garanti.
- L'utilisateur accepte un comportement légèrement différent de l'expérience macOS native : pas d'animation Mission Control entre les desktops virtuels (instantané), Mission Control native ignore les desktops virtuels roadie.
- BetterTouchTool (ou un équivalent) déclenche les commandes `roadie desktop focus N` via les raccourcis utilisateur ; roadie ne capture pas directement les hotkeys.

## Out of Scope

- **Multi-display** : tout ce qui concerne plusieurs écrans physiques avec leur propres desktops. Reporté en V3.
- **Création/destruction dynamique de desktops** : V2 fonctionne avec un nombre fixe (`count`) au démarrage. Création runtime reportée.
- **Bascule entre Mac Spaces natifs** : roadie n'observe pas et ne contrôle pas les Spaces natifs macOS. Hors scope définitif (le pivot est précisément de s'en affranchir).
- **Window→desktop pinning par règle de configuration** (ex : "Slack toujours sur desktop 3") : reporté V2.1.
- **Animation de transition** entre desktops : la bascule est instantanée par design (alignée AeroSpace). Animation reportée si demandée.
- **Drag-and-drop d'une fenêtre vers un autre desktop via UI** : nécessite une UI graphique non prévue. Possibilité de scripter via `roadie window assign --desktop N` reportée V2.1.

## Research Findings

### Régression macOS Tahoe documentée

- **yabai issue #2656** (ouverte, sans réponse upstream à mai 2026) : sur macOS 26 Tahoe, `CGSManagedDisplaySetCurrentSpace` change le state interne (visible sur SketchyBar et app active) **mais** WindowServer ne déclenche plus le rerender des fenêtres. Le space change officiellement mais l'utilisateur voit toujours les fenêtres de l'ancien space. Reproduit sur cette installation.
- **Conséquence** : le paradigme "1 Roadie Desktop = 1 Mac Space natif, bascule via SkyLight" est cassé par Apple. Pas de fix possible sans Apple ou sans pivot.

### Validation du pattern AeroSpace

- **AeroSpace** (window manager macOS open-source, ~17k stars) utilise depuis sa première release le pattern "tous les workspaces dans un seul Mac Space natif, hide/show via déplacement offscreen". Marche sur macOS 13/14/15/26 sans modification SIP, sans scripting addition, sans permissions privilégiées.
- **Marché** : ~10 % des utilisateurs power-user macOS de tiling window managers utilisent AeroSpace ; le pattern est validé en production sur des dizaines de milliers d'installations.
- **Limites connues d'AeroSpace** : "ghost windows" sur Tahoe (issue #1471) lorsqu'une fenêtre est fermée pendant qu'elle est offscreen — roadie peut éviter ce problème via observation AX `kAXUIElementDestroyedNotification` et nettoyage immédiat du registry.

### Red flags surveillés

- **Conflit avec Stage Manager Apple natif** : si l'utilisateur active Stage Manager macOS, le système peut interférer avec les positions de fenêtres roadie. Recommandation : désactiver Stage Manager Apple. Documenté dans Assumptions.
- **Apps qui repaint forcément on-screen** (rare, ex : certains lecteurs vidéo plein écran) : peuvent ramener leur fenêtre on-screen indépendamment de roadie. Edge case documenté.
- **Performance avec > 50 fenêtres total** : non testé. Le scope V2 cible ≤ 30 fenêtres au total, performance au-delà non garantie ; cap optionnel via config en V2.1 si besoin.
