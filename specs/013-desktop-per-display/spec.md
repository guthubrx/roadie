# Feature Specification: Desktop par Display (mode global ↔ per_display)

**Feature Branch**: `013-desktop-per-display`
**Created**: 2026-05-02
**Status**: Draft
**Dependencies**: SPEC-011 (virtual-desktops), SPEC-012 (multi-display)
**Input**: User description : « pouvoir avoir le choix en paramétrage soit mode global, soit mode séparé. Drag = la fenêtre adopte le desktop cible. Débranchement écran → migration vers primary, mais l'état de l'écran absent reste persisté ; au rebranchement, les fenêtres qui y étaient avant retournent dessus à leur expectedFrame. »

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Activer le mode per_display (Priority: P1)

L'utilisateur édite `~/.config/roadies/roadies.toml`, ajoute `mode = "per_display"` dans la section `[desktops]` et redémarre le daemon. À partir de là, `roadie desktop focus 2` ne change le desktop courant que sur l'écran où se trouve la fenêtre focalisée. Les autres écrans gardent leur desktop inchangé. L'utilisateur peut donc avoir desktop 1 affiché sur le grand écran et desktop 3 sur l'écran intégré simultanément.

**Why this priority** : Cœur fonctionnel de la feature. Sans ce comportement, la spec n'a pas d'utilité. C'est le MVP.

**Independent Test** : Avec 2 écrans connectés, créer une fenêtre sur chaque écran sur des desktops différents, faire `roadie desktop focus N` depuis chaque écran et constater visuellement que seul l'écran ciblé bascule.

**Acceptance Scenarios** :

1. **Given** mode `per_display` activé et 2 écrans (built-in desktop 1, LG desktop 1), **When** la frontmost est sur le LG et l'utilisateur fait `roadie desktop focus 2`, **Then** seules les fenêtres du LG sont cachées/affichées (built-in inchangé) et `roadie desktop list` montre LG=2, built-in=1.
2. **Given** mode `per_display`, frontmost sur le built-in desktop 1, **When** `roadie desktop focus 3`, **Then** seules les fenêtres built-in basculent ; LG reste sur son desktop courant.
3. **Given** mode `global` (défaut), 2 écrans desktop 1, **When** `roadie desktop focus 2` peu importe le focus, **Then** les fenêtres des 2 écrans basculent simultanément (régression V2 conservée).

---

### User Story 2 — Drag cross-écran adopte le desktop cible (Priority: P1)

En mode `per_display`, l'utilisateur drag une fenêtre du LG (qui est sur desktop 1) vers le built-in (qui est sur desktop 3). Au lâcher, la fenêtre **change de desktop** pour adopter le desktop courant du built-in (= 3) et reste donc visible sur le built-in. Sans ce comportement, la fenêtre disparaîtrait visuellement (puisque LG continue à afficher desktop 1 et built-in continue à afficher desktop 3 mais la fenêtre est encore "tagguée" desktop 1).

**Why this priority** : Indispensable pour que le mode `per_display` soit utilisable en pratique. Sans ça, l'utilisateur perd ses fenêtres sans comprendre pourquoi. AeroSpace fait pareil.

**Independent Test** : 2 écrans sur des desktops différents, drag une fenêtre cross-écran, vérifier qu'elle reste visible et que `roadie windows list` indique le nouveau `desktopID`.

**Acceptance Scenarios** :

1. **Given** mode `per_display`, fenêtre F sur LG desktop 1, built-in sur desktop 3, **When** l'utilisateur drag F vers le built-in, **Then** F est marquée `desktopID=3` et reste visible.
2. **Given** mode `per_display`, **When** `roadie window display N` est appelé, **Then** la fenêtre adopte le desktop courant du display cible (cohérent avec drag).
3. **Given** mode `global`, **When** drag cross-écran, **Then** la fenêtre garde son desktopID (pas de changement, comportement V2).

---

### User Story 3 — Recovery écran débranché/rebranché (Priority: P1)

L'utilisateur débranche son écran externe LG. Roadie détecte la perte et migre toutes les fenêtres LG vers le primary (built-in) à leur expectedFrame ajustée. **L'état persisté du LG (son current desktop, ses fenêtres assignées) reste sauvegardé sur disque sous son UUID**. Quelques minutes plus tard, l'utilisateur rebranche le LG. Roadie détecte le rebranchement, lit l'état persisté du LG, et **restaure les fenêtres qui y étaient avant débranchement** sur le LG à leur expectedFrame d'origine. Le current desktop du LG est aussi restauré.

**Why this priority** : Scénario quotidien (laptop branché/débranché du dock) — sans ça, l'utilisateur perd son layout chaque débranchement. C'est l'apport unique vs SPEC-012 qui ne préservait pas l'historique par-écran.

**Independent Test** : Configurer LG desktop 2 avec 3 fenêtres, débrancher → fenêtres vers built-in, rebrancher LG → 3 fenêtres reviennent sur LG, current = 2.

**Acceptance Scenarios** :

1. **Given** LG desktop 2 avec fenêtres F1/F2/F3 assignées, **When** LG est débranché, **Then** F1/F2/F3 sont sur le built-in à des frames clampées dans le visibleFrame du built-in, et l'état LG est conservé dans `displays/<lgUUID>/desktops/2/state.toml`.
2. **Given** LG débranché précédemment, fenêtres déjà sur built-in, **When** LG est rebranché, **Then** F1/F2/F3 retournent automatiquement sur le LG à leur expectedFrame mémorisée, et le current du LG est restauré à 2.
3. **Given** LG débranché, F2 est tué (process Cmd+Q), **When** LG rebranché, **Then** F1/F3 reviennent (F2 est ignorée silencieusement, pas d'erreur).
4. **Given** mode `global`, **When** débranchement/rebranchement, **Then** comportement identique à SPEC-012 (migration → primary, pas de restoration spéciale ; state global non lié à un display).

---

### User Story 4 — Migration ascendante V2 → V3 (Priority: P2)

Au premier boot du daemon V3, l'utilisateur a déjà un layout V2 dans `~/.config/roadies/desktops/<id>/state.toml`. Le daemon détecte cette structure legacy, déplace automatiquement les fichiers vers `~/.config/roadies/displays/<primaryUUID>/desktops/<id>/state.toml`, et préserve donc la totalité du layout V2 sans intervention utilisateur. Le mode par défaut reste `global`, garantissant zéro régression de comportement perçu.

**Why this priority** : Indispensable pour ne pas casser les utilisateurs V2 existants au upgrade. Mais le risque est circonscrit : c'est une migration one-shot.

**Independent Test** : Placer un état V2 manuellement, démarrer V3, vérifier que `displays/<primaryUUID>/desktops/N/state.toml` contient l'état V2 et que `desktops/N/state.toml` legacy n'existe plus (ou est marqué migré).

**Acceptance Scenarios** :

1. **Given** layout V2 (3 desktops avec 6 fenêtres) dans `desktops/`, mode `global` par défaut, **When** V3 démarre la première fois, **Then** les fichiers sont déplacés sous `displays/<primaryUUID>/` et le daemon démarre exactement comme en V2 (current = même desktop, mêmes fenêtres assignées).
2. **Given** migration déjà effectuée, **When** V3 redémarre, **Then** la migration est skippée (idempotent ; détecte l'absence de l'ancien dossier).

---

### User Story 5 — Visibilité de l'état per-display (Priority: P2)

`roadie desktop list` affiche maintenant une colonne par display indiquant quel desktop est courant sur chaque écran. `roadie desktop current` (sans `--json`) retourne le current du display où la frontmost est positionnée. Les events `desktop_changed` poussés via `roadie events --follow` incluent un champ `display_id` indiquant quel écran a basculé.

**Why this priority** : Sans cette UX, l'utilisateur ne sait pas dans quel état chaque écran est en mode `per_display`. SketchyBar et menu bars custom dépendent de l'event `display_id`.

**Independent Test** : `roadie desktop list` doit montrer 2 colonnes (par display) en multi-écran. `roadie events --follow` doit émettre `{"event":"desktop_changed","display_id":"...","to":"2",...}` à chaque focus.

**Acceptance Scenarios** :

1. **Given** mode `per_display`, 2 écrans, **When** `roadie desktop list`, **Then** sortie tabulaire avec une colonne `CURRENT[built-in]` et `CURRENT[LG]`.
2. **Given** `roadie events --follow` actif, **When** focus desktop 2 sur LG, **Then** un event `desktop_changed` JSON-line avec `display_id=4` est émis sur stdout.

---

### Edge Cases

- **Mode `per_display`, l'écran de la frontmost est introuvable** (race entre AX event et display unplug) : fallback sur le primary display, log un warn.
- **Mode `per_display`, aucune fenêtre frontmost** (boot, dock activé seul) : `roadie desktop focus N` cible le primary (cohérent avec mono-display).
- **Switch de mode `global` ↔ `per_display` à chaud** (reload config) : les `currentByDisplay` actuels sont préservés. En passage `global → per_display`, chaque display garde son current ; en `per_display → global`, on garde le current du primary comme valeur globale.
- **Drag d'une fenêtre tilée vers un display sur un desktop vide** : la fenêtre est insérée dans l'arbre BSP du display cible (utilise le mécanisme de SPEC-012 onDragDrop déjà en place + adopte le nouveau desktopID).
- **Rebranchement après un long sommeil** : si l'écran est rebranché plusieurs heures plus tard, le state.toml du display est toujours valide (pas d'expiration). Si le contenu pointe vers des wid morts, ils sont ignorés silencieusement.
- **Fenêtre commune à un stage cross-display** (cas pathologique) : les stages restent intra-desktop ; un stage du desktop 1 du LG ne fusionne pas avec un stage du desktop 1 du built-in, ils sont distincts (par display × desktop).
- **3+ écrans** : la spec supporte N écrans sans changement structurel (la map `currentByDisplay` est dynamique).
- **Config TOML invalide pour `mode`** : valeur inconnue (ex: `mode = "weird"`) → fallback sur `global` + warn dans les logs.

## Requirements *(mandatory)*

### Functional Requirements

#### Mode et configuration

- **FR-001** : System MUST accepter un champ `mode` dans `[desktops]` du TOML avec les valeurs `"global"` ou `"per_display"`. Défaut : `"global"`.
- **FR-002** : System MUST fallback sur `"global"` + log un warn si la valeur est invalide.
- **FR-003** : System MUST supporter le reload du mode à chaud sans perte d'état (commande `roadie daemon reload`).

#### Modèle de données

- **FR-004** : `DesktopRegistry` MUST maintenir une map `currentByDisplay: [CGDirectDisplayID: Int]` (clé = displayID, valeur = desktopID courant).
- **FR-005** : En mode `global`, tous les `currentByDisplay[*]` MUST avoir la même valeur (synchronisée à chaque mutation).
- **FR-006** : En mode `per_display`, chaque entry est mutée indépendamment.

#### Sémantique des commandes

- **FR-007** : `roadie desktop focus N` en mode `per_display` MUST changer uniquement `currentByDisplay[displayOfFrontmost]`. Le hide/show concerne uniquement les fenêtres dont le `state.frame.center` tombe sur ce display.
- **FR-008** : `roadie desktop focus N` en mode `global` MUST changer toutes les valeurs de `currentByDisplay` simultanément (= behavior V2).
- **FR-009** : `roadie desktop current` MUST retourner le current du display de la frontmost en `per_display`, ou la valeur globale en `global`.
- **FR-010** : `roadie desktop list` MUST afficher une colonne par display avec son current.

#### Drag & window display N

- **FR-011** : Lors d'un drag cross-display détecté par `onDragDrop`, en mode `per_display`, le `desktopID` de la fenêtre MUST être mis à jour à `currentByDisplay[targetDisplayID]`.
- **FR-012** : `roadie window display N` MUST adopter le `currentByDisplay[N]` comme nouveau desktopID de la fenêtre déplacée, en mode `per_display`.
- **FR-013** : En mode `global`, le `desktopID` de la fenêtre n'est PAS modifié lors d'un drag cross-display (compat V2).

#### Persistance per-display

- **FR-014** : System MUST persister l'état dans `~/.config/roadies/displays/<displayUUID>/desktops/<id>/state.toml` (un fichier par display × desktop).
- **FR-015** : System MUST persister `currentByDisplay` dans `~/.config/roadies/displays/<displayUUID>/current.toml` (un fichier par display).
- **FR-016** : System MUST déclencher la persistance à chaque focus change, drag cross-display, et debranchement.

#### Recovery branchement/débranchement

- **FR-017** : Au démarrage, pour chaque display physiquement présent, System MUST charger `displays/<uuid>/current.toml` (current desktop) et lire ses `state.toml` (fenêtres assignées).
- **FR-018** : Au `didChangeScreenParameters` détectant un nouvel écran, System MUST charger l'historique persisté de cet UUID et restaurer les fenêtres qui y étaient (matching par cgWindowID OU bundleID+title si cgWindowID a changé).
- **FR-019** : Au `didChangeScreenParameters` détectant un écran retiré, System MUST migrer les fenêtres vers le primary (logique SPEC-012 T027) MAIS conserver intact le state.toml du display retiré sur disque.
- **FR-020** : System MUST ignorer silencieusement les wid orphelins du state.toml au rebranchement (process tués entre-temps).

#### Migration V2 → V3

- **FR-021** : Au premier boot V3 détectant des fichiers dans `~/.config/roadies/desktops/<id>/`, System MUST déplacer ces fichiers vers `~/.config/roadies/displays/<primaryUUID>/desktops/<id>/`.
- **FR-022** : La migration MUST être idempotente : un boot subséquent ne doit rien faire (détecte l'absence de l'ancien dossier).
- **FR-023** : La migration MUST préserver tous les champs des state.toml legacy.

#### Events

- **FR-024** : System MUST émettre `desktop_changed` avec un payload incluant `{from, to, display_id, ts}` à chaque focus.
- **FR-025** : System MUST conserver les events SPEC-012 existants (`display_changed`, `display_configuration_changed`).

#### Compatibilité ascendante

- **FR-026** : Mode `global` (défaut) MUST garantir zéro régression observable depuis SPEC-011 et SPEC-012.
- **FR-027** : Tous les raccourcis BTT existants (Cmd+1..9, ⌥+1/2, ⌃⌥⌘+1..9, ⌘⇧+H/J/K/L, ⌥+W/V/F, ⇧⌥+F) MUST fonctionner sans modification dans les deux modes.

### Key Entities

- **`DisplayPersistenceRoot`** : Dossier `~/.config/roadies/displays/<displayUUID>/` contenant `current.toml` (current desktop pour ce display) et `desktops/<id>/state.toml` (fenêtres assignées au desktop N de ce display).
- **`DesktopRegistry.currentByDisplay`** : Map `[CGDirectDisplayID: Int]` représentant l'état actif. Synchronisée en mode global, indépendante en `per_display`.
- **`DisplayMode`** : Enum `global | per_display` issu du TOML, lu et applicable à chaud.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** : En mode `per_display`, un changement de desktop sur un écran n'affecte aucune fenêtre des autres écrans (vérifiable par diff visuel + `roadie windows list` avant/après).
- **SC-002** : Au rebranchement d'un écran, **≥ 95 %** des fenêtres précédemment assignées y reviennent automatiquement (les ≤ 5 % restants = process tué entre-temps, ignoré silencieusement).
- **SC-003** : La migration V2 → V3 est transparente : un utilisateur V2 démarrant V3 ne perçoit **aucun changement** de comportement (mode `global` par défaut + state préservé).
- **SC-004** : `roadie desktop focus N` en mode `per_display` se complète en moins de **200 ms** (cohérent avec la métrique perf SPEC-011).
- **SC-005** : Aucune régression sur les 27 raccourcis BTT existants (validation manuelle ou test E2E).
- **SC-006** : Le switch de mode à chaud (`global` ↔ `per_display`) ne perd aucune fenêtre ni aucun état (state preserved).

## Assumptions

- Le `displayUUID` retourné par `CGDisplayCreateUUIDFromDisplayID` est stable entre branchements d'un même écran physique. Si l'écran a un firmware update qui change l'UUID, le state ancien sera ignoré (cas extrême, acceptable).
- L'utilisateur a au plus ~10 écrans physiques dans son histoire (taille raisonnable du dossier `displays/`). Pas de mécanisme de purge automatique des UUID jamais revus.
- macOS `didChangeScreenParametersNotification` fire dans les 1-3 secondes après un branchement/débranchement physique. Acceptable pour un workflow desktop.
- Une fenêtre AX a un `cgWindowID` stable durant la session daemon. Au rebranchement, on matche par `cgWindowID` en priorité ; fallback `bundleID + title` si la première match échoue (rare).
