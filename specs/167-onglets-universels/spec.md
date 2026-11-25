# Spec 167 — Onglets universels par tuile / colonne + fiabilisation du premier placement (apps lentes)

## Contexte & Problème

1. **Premier placement d’une app lente en mode non-arbre (`scrolling`, `masterStack`, `bsp`, `tabbed`)** :
   Lorsqu’une application lente au démarrage à froid (ex. `iTerm2` avec ~1,1 s de blocage AX) crée sa fenêtre brute sur un autre écran que sa stage assignée, le premier déplacement peut échouer en `ax_window_unavailable_or_quarantined`. Jusqu’ici `unreadyPlacementScopes` ne couvrait que `treeScopes` (`spatialBsp`), et `recordTransition` n’armait pas de reprise rapide `ax_ready_retry` ; 5 s plus tard `reconcileStableVisibleDisplayDrift` adoptait la fenêtre sur l’écran brut au lieu de terminer le rapatriement.
2. **Généralisation des onglets par tuile / colonne à tous les modes tuilés** :
   La Spec 165 a introduit l’empilement d’onglets dans les tuiles de `spatialBsp` (`BSPTree.tabGroup`). Les utilisateurs en mode `scrolling` (colonnes à onglets façon Niri), `masterStack` (Master ou cases du Stack à onglets) et `bsp` souhaitent bénéficier de la même mécanique d’onglets (empilement `⌥ Option`, dépôt sur barre, glisser-sortir, `roadie tab …`, menu clic droit barre de titre).

## Exigences fonctionnelles

### Lot A — Premier placement fiable sur apps lentes (tous modes tuilés)
- **FR-001** : Tout échec pré-AX (`status == .failed` avec `writtenFrames.entry == nil`, direct ou animé) arme immédiatement une reprise rapide `ax_ready_retry` (`0.15 s` → backoff borné) et prolonge `newWindowDriftGraceUntil`.
- **FR-002** : `unreadyPlacementScopes` couvre aussi tout scope tuilé non-arbre contenant une fenêtre en attente pré-AX (`preAXFailedTransitionWindows` ou `unreadyPlacementWindows`), purge `failedFrames` dès que `readFrame` réussit, et relance immédiatement le placement.
- **FR-003** : `reconcileStableVisibleDisplayDrift` n’adopte jamais une fenêtre encore présente dans `preAXFailedTransitionWindows` ou `unreadyPlacementWindows`.

### Lot B — Onglets universels par slot (`scrolling`, `masterStack`, `bsp`, + `spatialBsp` préservé)
- **FR-004** : Les modes `scrolling`, `masterStack` et `bsp` supportent les groupes d’onglets par tuile/colonne via le modèle `PersistentStage.groups` (`WindowGroup` avec `presentation == "tabbed"`), rétrocompatible 100 % avec `stages.json`. `spatialBsp` conserve son `BSPTree.tabGroup` sans régression ; `tabbed` conserve sa barre globale unique ; `float` reste hors tuilage.
- **FR-005** : Une couche pure `LayoutTabSlots` dans `RoadieTiler` réduit les fenêtres d’une stage en *slots* (1 fenêtre seule ou 1 groupe d’onglets ≥ 2 fenêtres vivantes), délègue le placement géométrique à la stratégie du mode (`scrolling` avec `clipsLeft`/`clipsRight`, `masterStack`, `bsp`), réserve `tabBarHeight + 4 pt` en haut de chaque slot à onglets et calcule les `LayoutTabBarPlacement` exacts. Un groupe réduit à `< 2` fenêtres vivantes se replie automatiquement en tuile simple sans barre.
- **FR-006** : `StageTabBarController` affiche simultanément toutes les barres d’onglets des groupes actifs en `scrolling`, `masterStack` et `bsp` (clic de focus, réordonnancement par glisser horizontal, détachement par glisser-sortir).
- **FR-007** : `WindowCommandService` étend `tabCycle` (`next`/`prev`), `tabStack`, `tabUnstack`, `tabMove`, `tabReorder`, `availableTabStackDirections` et la synchronisation de l’onglet actif au `focus` aux modes `scrolling`, `masterStack` et `bsp`. En navigation directionnelle `focus`, les fenêtres masquées derrière un onglet actif d’un autre slot sont sautées au profit de l’onglet actif du slot voisin.
- **FR-008** : `DropPreviewController` permet d’empiler en `.stackTab` dans `scrolling`, `masterStack` et `bsp` par maintien de `⌥ Option` au centre d’une tuile/colonne ou dépôt direct sur une barre d’onglets existante, et de détacher un onglet en le glissant hors de sa barre.
- **FR-009** : `TitlebarContextMenuController` propose le sous-menu **Onglets** (empiler vers une tuile/colonne voisine, détacher cet onglet) sur tous les modes supportant les onglets par tuile (`spatialBsp`, `scrolling`, `masterStack`, `bsp`).

## Critères d’acceptation (Gherkin)

```gherkin
Scenario: App lente ouverte sur un autre écran en mode scrolling
  Given un Mac avec 2 écrans côte à côte et la stage active de l'écran 1 en mode scrolling
  When une nouvelle fenêtre apparaît sur l'écran 2 et échoue son premier placement pré-AX
  Then Roadie arme une reprise rapide ax_ready_retry (<= 0.2 s)
  And la réconciliation anti-dérive ne vole pas la fenêtre vers l'écran 2 tant qu'elle n'est pas placée
  And dès que AX répond, la fenêtre est rapatriée sur l'écran 1

Scenario: Colonnes à onglets en mode scrolling et tuiles à onglets en masterStack / bsp
  Given une stage en mode scrolling, masterStack ou bsp contenant 3 fenêtres
  When l'utilisateur empile deux fenêtres en onglets (roadie tab stack ou Option + dépôt)
  Then la stratégie place 2 slots (1 slot simple + 1 slot à onglets avec réserve tabBarHeight + 4 pt)
  And StageTabBarController affiche la barre d'onglets du groupe au-dessus de son slot
  And roadie tab next / prev, tab move, tab unstack et le clic barre fonctionnent
  And en mode scrolling multi-écrans, aucune barre ni fenêtre du groupe ne déborde sur l'écran voisin
```
