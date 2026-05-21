# Spécification Fonctionnelle : Durcissement de stabilité layout

<!-- SPEC-FORMALISM:START -->
## Fiche Synthèse

Spec: 010-layout-stability-hardening
Titre: Durcissement de stabilité layout
Statut: Implemented
Priorité: P0
Tâches: 47/47 (100%)
Tests: Couverture ciblée par `LayoutMaintainerTests`, `SnapshotServiceTests`, `DropPreviewEngineTests`, `DisplayParkingServiceTests`, `TilingPolicyTests`, `PowerUserDesktopCommandTests`

Résumé:
- Contexte: plusieurs correctifs ont été livrés pour empêcher Roadie de reprendre la main contre l'utilisateur lors des resize, drag/drop, changements de stage, changements d'écran, popups système et disparition de fenêtres.
- Objectif: documenter et rattacher ces correctifs transverses afin que le comportement attendu soit explicite, testable et non mélangé artificiellement avec Target Mode ou Display Parking.
- Dépendances: SPEC-003, SPEC-007, SPEC-008, SPEC-009

Fichiers:
- spec.md: ✓
- plan.md: ✓
- tasks.md: ✓
<!-- SPEC-FORMALISM:END -->

**Branche** : `main`
**Créée le** : 2026-05-20
**Statut** : Implemented
**Priorité** : P0
**Type** : Reconstruction rétrospective d'artefacts à partir des commits et du worktree
**Entrée utilisateur** : "reprendre tout ce qui a été commité mais qui ne peut pas être rattaché à des spécifications existantes" et corriger les problèmes où Roadie relayout, déplace, cache ou réactive des fenêtres sans intention utilisateur.

## Scénarios Utilisateur & Tests

### Récit Utilisateur 1 - Respecter les resize et déplacements utilisateur en mutable BSP (Priorité : P0)

En tant qu'utilisateur, je veux que Roadie respecte mes redimensionnements et déplacements quand une stage est en `mutableBsp`, afin que le tiler ne repasse pas derrière moi en recréant un layout précédent.

**Pourquoi cette priorité** : c'est le cœur du problème observé. Si Roadie corrige automatiquement une géométrie que l'utilisateur vient d'imposer, le layout devient inutilisable.

**Test indépendant** : redimensionner ou déplacer une fenêtre dans une stage `mutableBsp`, puis vérifier que les proportions et l'ordre résultants sont adoptés ou propagés au lieu d'être écrasés par un ancien intent.

**Scénarios d'acceptation** :

1. **Étant donné** une stage `mutableBsp`, **lorsque** l'utilisateur redimensionne une séparation, **alors** Roadie adopte la nouvelle géométrie et propage les dimensions cohérentes aux voisins concernés.
2. **Étant donné** une commande Roadie explicite vient d'être exécutée, **lorsque** le maintainer reçoit un snapshot intermédiaire, **alors** il attend que l'intention de commande soit appliquée avant de déclarer le layout stable.
3. **Étant donné** une fenêtre est déplacée par drag/drop, **lorsque** la preview calcule la cible, **alors** elle utilise la géométrie persistée du layout plutôt que la frame transitoire sous la souris.

---

### Récit Utilisateur 2 - Ne pas gérer les petites fenêtres système comme des tuiles (Priorité : P0)

En tant qu'utilisateur, je veux que les popups, panneaux de progression et fenêtres système courtes restent flottants, afin qu'une copie Finder, VeraCrypt, Word ou Little Snitch ne fasse pas sauter tout le layout.

**Pourquoi cette priorité** : ces fenêtres sont souvent temporaires, non redimensionnables ou sans plein écran utile. Les insérer dans le BSP provoque des oscillations et des zones de drop fausses.

**Test indépendant** : créer un `AXStandardWindow` court, sans bouton plein écran exploitable et avec chrome de fenêtre, puis vérifier qu'il est exclu du tiling et de la membership stage gérée.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre de progression courte non plein écran, **lorsque** Roadie construit son snapshot, **alors** elle n'est pas candidate au tiling.
2. **Étant donné** une fenêtre exclue par la politique de tiling, **lorsque** Roadie calcule les fenêtres gérées par stage, **alors** cette fenêtre ne pollue plus la stage ni les previews de drop.
3. **Étant donné** une fenêtre flottante est déplacée, **lorsque** la souris passe sur le layout, **alors** Roadie ne propose pas de cible verte destinée à réinsérer cette fenêtre.

---

### Récit Utilisateur 3 - Isoler les écrans et stages lors des disparitions de fenêtres (Priorité : P0)

En tant qu'utilisateur multi-écran, je veux qu'une fenêtre fermée ou disparue sur un écran ne change pas le stage, le focus ou le layout d'un autre écran, afin que les displays restent indépendants.

**Pourquoi cette priorité** : plusieurs incidents venaient d'une fenêtre cachée ou disparue qui réactivait une stage sur un autre écran, donnant l'impression que Roadie "ramenait tout" ailleurs.

**Test indépendant** : simuler une fenêtre marquée manquante sur un écran pendant qu'une fenêtre cachée d'un autre écran est encore focusée par macOS, puis vérifier que Roadie supprime cette réactivation croisée.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre vient d'être marquée manquante, **lorsque** macOS signale le focus sur une fenêtre cachée d'un autre écran, **alors** Roadie refuse de suivre ce focus caché.
2. **Étant donné** une stage est restaurée sur un écran, **lorsque** Roadie cache les stages inactives, **alors** il ne cache que les fenêtres du même écran.
3. **Étant donné** une fenêtre disparaît d'une stage, **lorsque** Roadie relayout les fenêtres restantes, **alors** il ne touche pas les autres scopes d'écran.

---

### Récit Utilisateur 4 - Cacher les fenêtres inactives sans artefacts visibles (Priorité : P1)

En tant qu'utilisateur, je veux que les fenêtres cachées par Roadie restent réellement hors de vue, afin de ne pas voir de barres de titre ou morceaux de fenêtres en bas à gauche.

**Pourquoi cette priorité** : le parking historique en bas/gauche laissait parfois macOS remonter la barre de titre dans une zone visible. La stratégie doit être centralisée et migrer les anciennes positions.

**Test indépendant** : prendre une fenêtre parkée avec l'ancien schéma bas/gauche, lancer un tick, puis vérifier qu'elle est déplacée vers le nouveau parking horizontal au bord droit du bureau virtuel.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre inactive doit être cachée, **lorsque** Roadie calcule sa frame de parking, **alors** elle est placée sur le bord droit du bureau virtuel et non plus en bas/gauche.
2. **Étant donné** une ancienne fenêtre cachée est détectée dans l'ancien parking, **lorsque** le maintainer tourne, **alors** il la migre vers le nouveau parking.
3. **Étant donné** plusieurs composants Roadie cachent des fenêtres, **lorsque** ils calculent la destination, **alors** ils utilisent tous la même primitive `HiddenWindowPlacement`.

---

### Récit Utilisateur 5 - Stabiliser les changements de stage visibles et le navrail (Priorité : P1)

En tant qu'utilisateur, je veux que les raccourcis et clics du navrail suivent l'ordre visible réellement affiché, afin d'éviter les stages invisibles, vides ou non tileables entre deux éléments visibles.

**Pourquoi cette priorité** : l'utilisateur raisonne par l'ordre de ce qu'il voit dans le navrail, pas par les IDs historiques ni les stages filtrées.

**Test indépendant** : construire un état avec stages vides, non tileables ou filtrées, puis vérifier que `switch-visible up/down` et les commandes par position ne traversent que les stages réellement visibles.

**Scénarios d'acceptation** :

1. **Étant donné** un navrail affichant quatre stages visibles, **lorsque** l'utilisateur déclenche stage visible suivant/précédent, **alors** Roadie va directement à l'élément adjacent affiché.
2. **Étant donné** des stages vides ou non tileables existent dans l'état interne, **lorsque** l'utilisateur navigue par ordre visible, **alors** ces stages ne sont pas traversées.
3. **Étant donné** une commande de changement de stage vient de s'exécuter, **lorsque** le rail se rafraîchit, **alors** il ne retarde pas l'affichage de la nouvelle stage.

## Cas Limites

- Une fenêtre disparaît pendant qu'une commande de move/resize est encore en cours.
- macOS retourne temporairement une fenêtre cachée comme focused window.
- Une app crée une fenêtre courte standard mais sans bouton plein écran utile.
- Une fenêtre a une frame transitoire très loin du layout pendant un drag.
- Un écran disparaît puis revient pendant que des stages parkées anciennes existent déjà.
- Une stage visible contient uniquement des fenêtres non candidates au tiling.
- Une ancienne frame cachée utilise encore le parking bas/gauche historique.
- Le maintainer voit un layout partiellement appliqué par AX et ne doit pas le confondre avec un resize utilisateur.

## Exigences Fonctionnelles

- **FR-001** : Roadie DOIT distinguer une action utilisateur ou commande récente d'un drift spontané du layout.
- **FR-002** : Roadie DOIT retarder ou supprimer les relayouts automatiques quand `LayoutCommandActivity` indique qu'une commande explicite est active.
- **FR-003** : Roadie DOIT appliquer ou réessayer une intention de layout issue d'une commande avant de déclarer le scope stable.
- **FR-004** : Roadie DOIT adopter les géométries utilisateur en `mutableBsp` quand elles sont cohérentes avec une modification de resize ou de drag.
- **FR-005** : Roadie DOIT propager les resize `mutableBsp` aux voisins sans reconstituer brutalement un BSP équilibré.
- **FR-006** : Roadie DOIT exclure du tiling les petites fenêtres standard de type popup/progress qui ne peuvent pas devenir de vraies fenêtres document.
- **FR-007** : Roadie DOIT calculer les fenêtres stage-managed après application de la politique de tiling, pas depuis les fenêtres brutes.
- **FR-008** : Roadie DOIT empêcher une fenêtre exclue du tiling de rester membre effective d'une stage gérée.
- **FR-009** : Roadie DOIT empêcher les previews de drop de proposer des zones pour des fenêtres flottantes ou transitoires non gérées.
- **FR-010** : Roadie DOIT utiliser la frame persistée d'une fenêtre source pendant un drag `mutableBsp` pour calculer une preview stable.
- **FR-011** : Roadie DOIT supprimer le suivi de focus vers une fenêtre cachée d'un autre écran quand une fenêtre vient de disparaître du scope actif.
- **FR-012** : Roadie DOIT limiter les opérations de hide/restore stage au display concerné quand l'action est scoped.
- **FR-013** : Roadie DOIT relayout les fenêtres restantes après disparition d'une fenêtre sans toucher aux autres displays.
- **FR-014** : Roadie DOIT centraliser le placement des fenêtres cachées dans une primitive commune.
- **FR-015** : Roadie DOIT migrer les anciennes fenêtres cachées en bas/gauche vers le nouveau parking non visible.
- **FR-016** : Roadie DOIT préserver l'indépendance des écrans quand une action utilisateur concerne un seul écran.
- **FR-017** : Roadie DOIT faire correspondre les commandes de navigation visible à l'ordre visible du navrail.
- **FR-018** : Roadie DOIT ignorer les stages vides ou non tileables dans la navigation visible, sauf action explicite de création ou d'envoi vers une stage vide.
- **FR-019** : Roadie DOIT rafraîchir le navrail immédiatement après un changement de stage sans coupler ce rafraîchissement au relayout.
- **FR-020** : Roadie DOIT émettre des événements diagnostiques pour les suppressions de relayout, adoption mutable BSP, propagation resize, suppression de focus caché et récupération de stages parkées.

## Entités Clés

- **LayoutCommandActivity** : verrou temporel léger indiquant qu'une commande Roadie explicite est en cours ou vient de se terminer.
- **LayoutIntent** : intention persistée de positions attendues après une commande de layout ou de déplacement.
- **MutableBSP Geometry** : état géométrique mutable qui conserve les choix utilisateur de taille et position.
- **TilingPolicyContext** : politique d'éligibilité qui décide si une fenêtre est gérée ou flottante.
- **HiddenWindowPlacement** : stratégie unique de parking invisible des fenêtres cachées.
- **Visible Stage Order** : liste filtrée de stages réellement présentées à l'utilisateur dans le navrail.
- **Drop Preview Candidate** : proposition de destination visuelle pendant un drag, calculée uniquement pour les fenêtres gérées.

## Critères de Succès

- **SC-001** : Après un resize `mutableBsp`, Roadie ne restaure pas l'ancienne géométrie dans les 5 secondes suivantes sauf si l'utilisateur déclenche une commande explicite.
- **SC-002** : Une fenêtre courte de progression/copie standard est exclue du tiling et ne génère pas de cible de drop.
- **SC-003** : La fermeture d'une fenêtre sur un écran ne change pas la stage active d'un autre écran.
- **SC-004** : Une fenêtre cachée par Roadie ne laisse plus apparaître de barre de titre en bas/gauche après le tick de maintenance.
- **SC-005** : `stage switch-visible up/down` suit l'ordre du navrail affiché sans passer par des stages vides invisibles.
- **SC-006** : Les tests ciblés de snapshot, maintainer, preview, parking, tiling policy et stage navigation couvrent les régressions corrigées.

## Hypothèses

- `mutableBsp` devient le mode recommandé pour l'utilisateur qui veut déplacer et redimensionner librement.
- Les fenêtres flottantes restent visibles et manipulables par macOS, mais ne doivent pas déclencher de logique BSP.
- Les corrections doivent être génériques : aucune exception dédiée à Finder, VeraCrypt, Word, Little Snitch, Teams ou une app isolée.
- Les écrans doivent être traités comme scopes indépendants sauf commande explicite inter-écran.
- Les corrections de cette spec ne remplacent pas les fonctionnalités de SPEC-007 ; elles durcissent les interactions entre parking d'écran, snapshot et layout.
