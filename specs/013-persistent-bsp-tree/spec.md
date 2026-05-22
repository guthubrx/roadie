# Spécification de fonctionnalité : Arbre BSP persistant (yabai/i3-like)

**Branche** : `013-persistent-bsp-tree`
**Créé le** : 2026-05-22
**Statut** : Cadrage — implémentation en session dédiée (gros morceau, plusieurs jours)
**Entrée utilisateur** : "Je veux avoir le mode comme yabai ou i3 : la nouvelle fenêtre coupe le pane focalisé, l'arbre se souvient de sa structure, et je veux pouvoir choisir dans la config si l'insertion est à gauche ou à droite (mon défaut : à droite)."

## Contexte

Roadie a aujourd'hui des modes `bsp` et `mutableBsp`, mais **aucun ne fait du vrai BSP à arbre persistant**. Le moteur actuel reconstruit le layout à partir d'une **liste ordonnée** de fenêtres + leurs positions observées (`split_policy = "balanced" | "dwindle"`). Il n'a pas de mémoire de structure : il ne sait pas « quelle fenêtre a coupé quelle autre ». Conséquence : sur écran large, `balanced` produit N colonnes égales, et une nouvelle fenêtre se place selon sa position macOS, pas « à côté du focus ».

L'utilisateur veut le comportement yabai/i3 : un **arbre BSP persistant** où chaque nouvelle fenêtre divise **uniquement** le pane focalisé, les autres ne bougeant pas.

**Prérequis** : SPEC-012 (lifecycle unifié) doit être mergée pour éviter de réintroduire de la divergence entre les deux modes.

## Scénarios utilisateur et tests

### Scénario 1 — Insertion sur le pane focalisé (Priorité : P1)

L'utilisateur a plusieurs fenêtres tilées. Il en ouvre une nouvelle. Elle doit couper en deux **uniquement** la fenêtre actuellement focalisée ; toutes les autres gardent leur taille et position.

**Test indépendant** : 3 fenêtres tilées, focus sur l'une, ouvrir une 4e → seule la focalisée est divisée, les 2 autres inchangées.

**Scénarios d'acceptation** :
1. **Étant donné** une fenêtre focalisée occupant un pane, **Quand** une nouvelle fenêtre s'ouvre, **Alors** ce pane est divisé en deux (50/50) et les autres panes ne bougent pas.
2. **Étant donné** un arbre de plusieurs fenêtres, **Quand** on ferme une fenêtre, **Alors** son frère récupère l'espace libéré (et seulement lui).
3. **Étant donné** une fenêtre focalisée large (ratio > hauteur), **Quand** une fenêtre s'ouvre, **Alors** le split est vertical (côte à côte) ; si le pane est haut, le split est horizontal (empilé). (Comportement yabai : split selon la dimension dominante.)

### Scénario 2 — Direction d'insertion configurable (Priorité : P1)

L'utilisateur choisit dans sa config de quel côté la nouvelle fenêtre apparaît.

**Test indépendant** : `new_window_side = "right"` → nouvelle fenêtre à droite/en bas du pane divisé ; `"left"` → à gauche/en haut.

**Scénarios d'acceptation** :
1. **Étant donné** `new_window_side = "right"` (défaut), **Quand** une fenêtre s'ouvre, **Alors** elle prend la moitié droite (ou basse) du pane focalisé, l'existante garde la gauche (ou haut).
2. **Étant donné** `new_window_side = "left"`, **Quand** une fenêtre s'ouvre, **Alors** elle prend la moitié gauche (ou haute).

### Scénario 3 — Persistance et reconciliation de l'arbre (Priorité : P2)

L'arbre survit au polling, aux disparitions temporaires de fenêtres (fullscreen, changement de Space), et au redémarrage du daemon.

**Scénarios d'acceptation** :
1. **Étant donné** un arbre construit, **Quand** le daemon redémarre, **Alors** l'arbre est restauré depuis la persistance.
2. **Étant donné** une fenêtre disparaît temporairement puis revient, **Quand** elle revient, **Alors** elle retrouve sa place dans l'arbre (cohérent avec le grace period missing-windows existant).
3. **Étant donné** un écran déconnecté, **Quand** le parking heal s'exécute, **Alors** le sous-arbre de cet écran est préservé/migré sans corruption.

### Scénario 4 — Coexistence avec les modes existants (Priorité : P2)

Le nouveau mode n'écrase pas balanced/dwindle/masterStack/float.

**Scénarios d'acceptation** :
1. **Étant donné** `split_policy = "balanced"` (ou dwindle), **Quand** Roadie tile, **Alors** le comportement actuel est inchangé.
2. **Étant donné** le nouveau mode activé, **Quand** l'utilisateur bascule de mode, **Alors** la transition se fait sans perte de fenêtres.

### Cas limites

- Fermeture de la dernière fenêtre d'un sous-arbre : le nœud parent disparaît, l'oncle récupère l'espace.
- Fenêtre déplacée manuellement (resize) : l'arbre adopte le nouveau ratio (comportement mutableBsp préservé).
- Multi-écran : un arbre **par stage** (donc par scope display×desktop×stage).
- Groupes (SPEC-002 window groups) : un groupe occupe une feuille de l'arbre.

## Exigences

### Exigences fonctionnelles

**EF-001** Roadie DOIT maintenir un arbre BSP persistant par stage : nœuds internes (split horizontal/vertical + ratio), feuilles (fenêtre ou groupe).

**EF-002** Une nouvelle fenêtre DOIT diviser en deux la feuille focalisée, sans affecter les autres feuilles.

**EF-003** La fermeture d'une fenêtre DOIT faire récupérer l'espace par son frère dans l'arbre.

**EF-004** L'orientation du split DOIT suivre la dimension dominante du pane (large → split vertical, haut → split horizontal), comme yabai.

**EF-005** La config `[window_placement]` DOIT exposer `new_window_side = "right" | "left"` (défaut utilisateur : `right`).

**EF-006** L'arbre DOIT être persisté (dans `stages.json` ou un store dédié) et restauré au redémarrage.

**EF-007** L'arbre DOIT survivre au grace period missing-windows et au parking heal multi-écran sans corruption.

**EF-008** Les modes existants (`balanced`, `dwindle`, `masterStack`, `float`) DOIVENT rester disponibles et inchangés ; le nouveau comportement est un mode/policy supplémentaire (nom à décider en plan : `split_policy = "spatial"` ou nouveau `default_strategy`).

**EF-009** Les resize manuels DOIVENT être adoptés comme ratio du nœud correspondant (continuité avec mutableBsp).

### Critères de succès mesurables

**SC-001** Ouvrir une 4e fenêtre avec focus sur 1 des 3 existantes ne déplace QUE la focalisée (mesure : frames des 2 autres identiques avant/après, tolérance 2px).

**SC-002** `new_window_side = "right"` place la nouvelle fenêtre à droite/bas dans 100% des cas testés ; `"left"` à gauche/haut.

**SC-003** Après redémarrage du daemon, l'arbre est identique (mesure : sérialisation avant/après).

**SC-004** Les tests des modes existants (balanced/dwindle/masterStack/float) restent 100% verts.

**SC-005** 0 perte de fenêtre sur 50 cycles ouverture/fermeture aléatoires (test de fuzzing léger).

### Non-objectifs

- Pas de gestion des « insertion points » manuels avancés de yabai (`--insert`) dans cette itération.
- Pas de ré-architecture des autres stratégies.
- Pas de changement du mode atomique/monolithique (hérité de SPEC-012).

## Dépendances avec specs existantes

- **SPEC-012** (Lifecycle unifié) : **prérequis strict**. L'arbre se branche sur le tiler unifié.
- **SPEC-002** (Window groups) : une feuille de l'arbre peut être un groupe.
- **SPEC-010** (Layout stability hardening) : interaction avec le grace period missing-windows et le parking heal — à ne pas régresser.
- **SPEC-011** (Atomic components) : l'arbre est dans le code partagé, donc actif dans les deux modes.

## Risques majeurs (à détailler en plan.md)

- **Reconciliation arbre ↔ réalité AX** : la source de vérité reste les fenêtres réelles ; l'arbre doit se resynchroniser quand AX diverge (fenêtre fermée hors Roadie, déplacée par une autre app).
- **Interaction avec le parking/grace period** : risque de corruption d'arbre lors de déconnexions d'écran.
- **Migration depuis l'état actuel** : les stages existants (liste de fenêtres) doivent être convertis en arbre sans perte.

## Checklist de validation

- [ ] Scénarios couvrent insertion focalisée, direction, persistance, coexistence
- [ ] EF mesurables, SC avec seuils
- [ ] Dépendances SPEC-012/002/010/011 documentées
- [ ] Risques majeurs identifiés pour le plan
- [ ] Non-objectifs cadrent la première itération
