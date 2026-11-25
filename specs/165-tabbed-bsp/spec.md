# Feature Specification: Tabbed BSP (Tuiles à onglets intégrées dans `spatialBsp`)

**Feature Branch**: `feat/165-tabbed-bsp`  
**Created**: 2026-11-25  
**Status**: Active  
**Input**: Permettre de transformer n'importe quelle tuile d'un arbre BSP (`spatialBsp`) en conteneur d'onglets (style i3 / Hyprland / AeroSpace accordion-in-BSP), directement intégré par défaut dans `spatialBsp`, avec empilement intuitif (`⌥ Option` au centre ou dépôt sur une barre d'onglets existante), mini barre d'onglets par tuile, réordonnancement horizontal, détachement par glisser-sortir depuis la barre d'onglets vers une zone de dépôt BSP, commandes clavier dédiées `roadie tab`, lanceur et menu contextuel de barre de titre.

---

## Contexte & décisions utilisateur

Décisions validées avec l'utilisateur avant spécification :

1. **Portée (A1)** : Intégré directement dans `spatialBsp`, disponible partout par défaut sans nouveau mode de disposition. Une tuile simple (`.leaf`) reste identique au comportement actuel (aucune barre d'onglets affichée tant qu'elle ne contient qu'une seule fenêtre) ; dès qu'une deuxième fenêtre y est empilée, la tuile devient un groupe d'onglets (`.tabGroup`) avec sa propre mini barre d'onglets.
2. **Détachement interactif depuis la barre d'onglets (A1+)** : Glisser un onglet **hors** de la mini barre d'onglets d'une tuile déclenche l'aperçu de dépôt BSP habituel et permet de le détacher directement en tuile indépendante (à gauche, droite, haut, bas de sa propre tuile ou de n'importe quelle autre tuile, ou même de l'empiler sur une autre tuile). Glisser horizontalement **dans** la barre réordonne les onglets.
3. **Empilement intuitif (A2)** : Conserver **centre = échange (swap)** afin de préserver les habitudes existantes. Pour empiler une fenêtre glissée en onglet dans une tuile cible :
   - **Déposer sur la barre d'onglets** d'une tuile déjà ongletisée, OU
   - **Maintenir `⌥ Option`** en déposant sur le centre d'une tuile (simple ou déjà ongletisée).
   - L'aperçu visuel affiche une couleur dédiée (turquoise/cyan), un bandeau supérieur stylisé rappelant une barre d'onglets et un libellé explicite (« Empiler en onglet » / « Stack as tab »), et l'aperçu d'échange (centre sans `⌥`) rappelle discrètement l'indice `⌥ = onglet` / `⌥ = tab`.
4. **Navigation clavier (A3)** :
   - `roadie focus left|right|up|down` continue de sauter de **tuile BSP en tuile BSP** (atterrissant toujours sur l'onglet actif de la tuile voisine, jamais piégé dans les onglets).
   - Commandes dédiées : `roadie tab next`, `roadie tab prev`, `roadie tab stack <dir>`, `roadie tab unstack [dir]`, `roadie tab move left|right`, plus clic direct sur la mini barre d'onglets.

---

## User Scenarios & Testing

### User Story 1 — Empiler et naviguer dans une tuile à onglets BSP (Priorité : P1)

En tant qu'utilisateur en mode `spatialBsp`, je peux empiler deux ou plusieurs fenêtres dans une même tuile BSP pendant que mes autres tuiles restent normalement découpées à côté, et basculer d'un onglet à l'autre au clic ou au clavier.

**Independent Test**: Créer un arbre BSP avec 3 fenêtres `A`, `B`, `C`, empiler `C` sur `B`, vérifier que `A` conserve sa colonne, `B` et `C` partagent la même tuile sous une barre d'onglets réservée, et `tab next`/`tab prev` bascule l'onglet actif.

```gherkin
Feature: Tuiles à onglets dans spatialBsp

  Scenario: Empiler une fenêtre sur une tuile voisine
    Given une stage en mode spatialBsp contenant les tuiles A (gauche) et B (droite)
    And une troisième fenêtre C dans le même arbre
    When j'empile C sur B via `BSPTree.stacking(C, onto: B)` ou `roadie tab stack`
    Then l'arbre contient un `.tabGroup([B, C], active: C)` à la place de B
    And les frames calculées de B et C sont identiques sous la barre d'onglets réservée
    And la barre d'onglets de la tuile [B, C] est placée exactement en haut de la tuile
    And la tuile A ne possède aucune barre d'onglets

  Scenario: Repli automatique à une seule fenêtre
    Given une tuile `.tabGroup([B, C], active: C)`
    When C est fermée ou retirée de l'arbre
    Then la tuile redevient automatiquement une simple feuille `.leaf(B)`
    And aucune barre d'onglets n'est affichée pour B
    And B reprend toute la hauteur de la tuile sans réserve de barre

  Scenario: Navigation directionnelle non piégée et navigation dédiée aux onglets
    Given une tuile gauche `.leaf(A)` et une tuile droite `.tabGroup([B, C], active: C)`
    When j'exécute `roadie focus right` depuis A
    Then le focus arrive sur C (onglet actif de la tuile droite)
    When j'exécute `roadie tab prev`
    Then le focus bascule sur B et `active` devient B dans l'arbre persisté
    When j'exécute `roadie focus left`
    Then le focus revient directement sur A
```

### User Story 2 — Glisser-déposer intuitif : empiler (`⌥` / barre), réordonner et détacher (Priorité : P1)

En tant qu'utilisateur, je peux empiler une fenêtre à la souris en la glissant sur la barre d'onglets d'une tuile ou sur son centre avec `⌥ Option`, réordonner les onglets horizontalement dans la barre, et détacher un onglet en le tirant hors de sa barre vers n'importe quelle zone de dépôt BSP.

```gherkin
Feature: Glisser-déposer des onglets BSP

  Scenario: Empiler par dépôt sur le centre avec Option maintenu
    Given une stage spatialBsp avec deux tuiles A et B
    When je glisse A sur le centre de B avec la touche Option maintenue
    Then DropPreviewEngine propose l'opération `.stackTab` ciblant B
    And la mutation d'arbre produit `.tabGroup([B, A], active: A)`

  Scenario: Empiler par dépôt direct sur une barre d'onglets existante (sans Option)
    Given une stage spatialBsp avec une tuile simple A et une tuile à onglets [B, C]
    When je glisse A sur la barre d'onglets de la tuile [B, C] sans maintenir Option
    Then DropPreviewEngine propose l'opération `.stackTab` ciblant la tuile [B, C]
    And la mutation d'arbre produit `.tabGroup([B, C, A], active: A)`

  Scenario: Conserver l'échange au centre sans Option
    Given une stage spatialBsp avec deux tuiles A et B
    When je glisse A sur le centre de B sans maintenir Option
    Then DropPreviewEngine propose l'opération `.swap`

  Scenario: Détacher un onglet par glisser hors de sa barre d'onglets
    Given une tuile à onglets [A, B] dans une stage spatialBsp
    When je saisis l'onglet A dans la mini barre et le glisse vers le bord droit de la tuile
    Then DropPreviewEngine propose `.insertRight` ciblant B
    And au relâchement la tuile se scinde en B (gauche) et A (droite) sans barre d'onglets

  Scenario: Réordonner horizontalement dans la barre d'onglets
    Given une tuile à onglets [A, B, C]
    When je glisse l'onglet C vers la position 0 dans la barre d'onglets
    Then l'ordre des onglets devient [C, A, B]
```

### User Story 3 — Compatibilité complète avec les opérations BSP et le reste de Roadie (Priorité : P2)

Toutes les fonctionnalités existantes de `spatialBsp` (séparations à la souris `BSPDivider`, redimensionnement natif `BSPNativeResize`, rotation 90°, miroir X/Y, égalisation `balance`, minimums connus `SizedTree`, persistance `stages.json`, sauvegarde/réouverture de scènes `StageProject`, mode `.tabbed` global de Spec 164) continuent de fonctionner sans régression et supportent `.tabGroup`.

```gherkin
Feature: Intégrité BSP et rétrocompatibilité

  Scenario: Rétrocompatibilité JSON de stages.json
    Given un fichier stages.json créé avant Spec 165 ne contenant que empty/leaf/split
    When il est décodé par le nouveau BSPTree
    Then l'arbre décodé est strictement identique et aucun changement de géométrie n'a lieu

  Scenario: Redimensionnement et séparations sur un arbre contenant un tabGroup
    Given un arbre split(vertical, 0.5, leaf(A), tabGroup([B, C], active: B))
    When je calcule `dividers`, `movingDivider`, `BSPNativeResize` et `adjustingFence`
    Then la séparation entre A et [B, C] est détectée et déplaçable
    And le redimensionnement met à jour A ainsi que B et C ensemble dans la tuile droite

  Scenario: Sauvegarde et restauration d'une scène StageProject avec onglets
    Given une stage contenant une tuile `.tabGroup([B, C], active: C)`
    When la scène est capturée via `StageProject.capture` puis restaurée via `tree(for:)`
    Then le `.tabGroup` et son onglet actif sont préservés
```

---

## Requirements

- **FR-001 (Modèle `BSPTree.tabGroup`)**: Ajouter `case tabGroup(windowIDs: [WindowID], active: WindowID)` à `BSPTree` avec invariant de normalisation (0 → `.empty`, 1 → `.leaf`, dédoublonnage ordonné, `active` toujours membre de `windowIDs`), 100 % rétrocompatible `Codable`.
- **FR-002 (Géométrie & barre d'onglets par tuile)**:
  - `BSPTree.place(in:innerGap:tabBarHeight:minimumSizes:)` (défaut `tabBarHeight = 0`) réserve en haut de chaque `.tabGroup` (≥ 2 fenêtres, `tabBarHeight > 0`, hauteur tuile ≥ `tabBarHeight + 120`) une bande de `min(tabBarHeight, floor(rect.height / 4))` + un interstice de `4 pt`, et place toutes les fenêtres du groupe sur le rectangle de contenu inférieur.
  - `BSPTree.tabBarFrames(in:innerGap:tabBarHeight:minimumSizes:)` retourne la liste exacte des barres d'onglets (`BSPTabBarPlacement`: `windowIDs`, `active`, `barFrame`, `tileFrame`) comme source de vérité unique partagée par `StageTabBarController` et `DropPreviewEngine`.
  - `SizedTree` intègre la hauteur réservée de la barre dans le minimum vertical d'un `.tabGroup`.
  - Pour tout arbre sans `.tabGroup`, la géométrie produite reste strictement identique au pixel près.
- **FR-003 (Opérations pures sur onglets)**: Ajouter sur `BSPTree` :
  - `stacking(_ source: WindowID, onto target: WindowID) -> BSPTree`
  - `unstacking(_ window: WindowID, side: BSPInsertionSide, containerIsWide: Bool) -> BSPTree` et surcharge géométrique `in:innerGap:excluding:`
  - `selectingTab(_ window: WindowID) -> BSPTree`
  - `cyclingTab(from window: WindowID, delta: Int) -> (tree: BSPTree, nextActive: WindowID)?`
  - `reorderingTab(_ window: WindowID, delta: Int) -> BSPTree` et `reorderingTab(_ window: WindowID, toIndex: Int) -> BSPTree`
  - `tabGroup(containing:)`, `tabGroups`, `activeWindowIDs`.
- **FR-004 (Compatibilité complète des opérations BSP)**: Mettre à jour `BSPTree` (`windowIDs`, `contains`, `projected`, `removing`, `inserting`, `replacingLeaf`, `swapping`, `collectSplits`, `adoptingSplits`, `balanced`, `togglingSplit`, `settingSplit`, `adjustingFence`, `correctingForMinimumSize`, `ancestors`, `rotated90`, `mirrored`), `BSPDivider`, `BSPNativeResize`, `SpatialBSPLayoutStrategy`, et `StageProject`.
- **FR-005 (Synchronisation focus & réconciliation)**:
  - `SnapshotService.reconciledTree` synchronise `active` dans `bspTree` lorsque la fenêtre focalisée appartient à un `.tabGroup`.
  - `WindowCommandService.focus(windowID:)` et `treeNeighbor` ciblent l'onglet actif des tuiles voisines et mettent à jour `active` dans `bspTree`.
- **FR-006 (Multi-barres d'onglets & interactions directes)**:
  - `StageTabBarController` gère simultanément plusieurs barres par stage `spatialBsp` (une par `.tabGroup` avec ≥ 2 fenêtres vivantes), en plus du mode `.tabbed` global (Spec 164), avec `barID` unique par cible.
  - Clic sur un onglet → focus + mise à jour `active`.
  - Glisser horizontal dans la barre → réordonnancement des onglets (`reorderingTab`).
  - Glisser hors de la barre → session `DropPreviewController` en direct permettant de détacher l'onglet en tuile BSP à l'endroit déposé (y compris sur un bord de sa propre tuile ou vers une autre tuile / un autre écran).
- **FR-007 (Empilement par glisser-déposer)**:
  - `DropPreviewOperation.stackTab` déclenché lors d'un dépôt sur la `barFrame` d'un `.tabGroup` existant OU sur le centre d'une tuile avec `⌥ Option` maintenu.
  - Aperçu visuel distinct (couleur cyan/teal, bandeau de barre d'onglets simulé en haut, badge « Empiler en onglet » / « Stack as tab » ; et discret rappel `⌥ = onglet` / `⌥ = tab` sur l'aperçu `.swap` en mode arbre).
  - Au dépôt d'un `.stackTab`, la fenêtre source devient l'onglet actif et reçoit le focus.
- **FR-008 (CLI, Lanceur, Menu barre de titre, Complétion & Documentation)**:
  - CLI : `roadie tab next`, `roadie tab prev`, `roadie tab stack left|right|up|down`, `roadie tab unstack [left|right|up|down]`, `roadie tab move left|right`.
  - Lanceur : commandes « Onglet suivant », « Onglet précédent », « Empiler en onglet (gauche/droite/haut/bas) », « Détacher l'onglet en tuile ».
  - Menu contextuel barre de titre : sous-menu « Onglets » (en mode `spatialBsp` : empiler avec voisine disponible, détacher l'onglet si dans un groupe).
  - Documentation FR & EN mise à jour (`README.md`, `README.fr.md`, `docs/{fr,en}/cli.md`, `docs/{fr,en}/features.md`, `docs/{fr,en}/use-cases.md`).

---

## Edge Cases

- Empiler une fenêtre sur elle-même (`source == target`) → no-op.
- Empiler une fenêtre déjà dans le même `.tabGroup` que `target` → sélectionne simplement `source` comme onglet actif sans dupliquer.
- Fermer ou déplacer vers une autre stage l'onglet actif d'un groupe de 3 fenêtres → l'onglet adjacent (`min(index, remaining.count - 1)`) devient actif et le groupe reste à 2 fenêtres.
- Fermer un onglet d'un groupe de 2 fenêtres → repli automatique vers `.leaf(survivante)` et disparition immédiate de la barre d'onglets.
- Détacher un onglet (`unstack`) alors que la fenêtre n'est pas dans un `.tabGroup` → no-op propre (code de sortie 0).
- Tuile trop petite en hauteur (`< tabBarHeight + 120`) → ne réserve pas de barre (évite d'écraser le contenu), place les fenêtres sur la tuile complète.
- Glisser un onglet hors de sa barre puis le relâcher au centre de sa propre tuile → annulation propre (pas de swap absurde avec son propre co-onglet).
- Fenêtre en plein écran natif / temporairement absente dans un groupe de 2 → `projected(excluding:)` replie temporairement sur `.leaf(autre)` (barre masquée) tout en conservant le `.tabGroup` dans l'arbre persisté jusqu'à son retour.
