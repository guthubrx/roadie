# Spécification de fonctionnalité : Unification du cycle de vie des composants

**Branche** : `012-component-lifecycle-unification`
**Créé le** : 2026-05-22
**Statut** : Prêt pour planification
**Entrée utilisateur** : "On conserve les deux modes (monolithique + modulaire) mais on élimine la divergence : factoriser le démarrage des composants pour qu'un observer/timer ne soit ajouté qu'une seule fois et profite aux deux modes."

## Contexte

SPEC-011 a introduit le mode atomique (modulaire) : `roadied tiler`, `roadied rail`, etc. lancent chacun un composant dans son propre process. Le mode monolithique historique (`roadied run --yes`) lance tout dans un seul process.

Le démarrage de chaque composant est aujourd'hui **dupliqué** dans `Sources/roadied/main.swift` : un bloc de setup dans le `case "run"` ET un bloc dans la sous-commande dédiée. Cette duplication a causé **4 des 7 bugs corrigés le 2026-05-22** : la sous-commande `tiler` ne reproduisait pas le `displayChangeObserver` ni le live observer AX présents dans `run`, et les events de reconciliation étaient dupliqués. À chaque fois, un comportement présent côté monolithique manquait côté modulaire.

## Scénarios utilisateur et tests

### Scénario 1 — Parité de comportement entre les deux modes (Priorité : P1)

Un utilisateur lance Roadie soit en monolithique (`roadied run --yes`), soit en modulaire (`Scripts/start-modular`). Dans les deux cas, chaque composant doit se comporter **exactement pareil** : mêmes observers, mêmes timers, mêmes réactions aux events système.

**Pourquoi cette priorité** : la divergence actuelle est une source structurelle de bugs. Chaque feature touchant le lifecycle doit aujourd'hui être codée deux fois, et un oubli dans l'un des modes passe inaperçu.

**Test indépendant** : démarrer le tiler dans chaque mode, ouvrir une fenêtre / changer d'écran, vérifier que les events émis (`live_tick`, `display-change-heal`) sont identiques.

**Scénarios d'acceptation** :

1. **Étant donné** le tiler est lancé en monolithique, **Quand** une fenêtre apparaît, **Alors** un `live_tick` est émis en ~15-80ms.
2. **Étant donné** le tiler est lancé en modulaire, **Quand** une fenêtre apparaît, **Alors** un `live_tick` est émis en ~15-80ms (identique au monolithique).
3. **Étant donné** un écran est déconnecté, **Quand** l'événement survient, **Alors** un `display-change-heal` est déclenché dans les deux modes.

### Scénario 2 — Une seule source de vérité par composant (Priorité : P1)

Un développeur ajoute un nouvel observer ou modifie le démarrage d'un composant. Il doit le faire **à un seul endroit**, et les deux modes en bénéficient automatiquement.

**Pourquoi cette priorité** : c'est l'objectif central — supprimer la dette de duplication.

**Test indépendant** : inspecter `Sources/roadied/main.swift` — le setup de chaque composant ne doit apparaître qu'une fois, appelé par les deux modes.

**Scénarios d'acceptation** :

1. **Étant donné** le code de démarrage d'un composant, **Quand** on le lit, **Alors** il existe une seule fonction de démarrage par composant, sans duplication entre `run` et les sous-commandes.
2. **Étant donné** un nouvel observer ajouté à un composant, **Quand** on le branche, **Alors** aucune modification dupliquée n'est nécessaire pour les deux modes.

### Scénario 3 — Aucune régression fonctionnelle (Priorité : P1)

Le refactor ne doit RIEN changer au comportement observable. Les deux modes continuent de fonctionner exactement comme après les fixes du 2026-05-22.

**Test indépendant** : la suite de tests complète passe (428+ tests). `roadied run --yes` et `Scripts/start-modular` démarrent les mêmes composants qu'avant.

**Scénarios d'acceptation** :

1. **Étant donné** la suite de tests Swift, **Quand** elle est exécutée après le refactor, **Alors** 100% des tests passent.
2. **Étant donné** `roadied run --yes`, **Quand** il démarre, **Alors** il lance exactement les mêmes composants qu'avant le refactor.
3. **Étant donné** les flags `--no-*` et les sous-commandes, **Quand** ils sont utilisés, **Alors** leur comportement est inchangé.

### Cas limites

- Un composant nécessite un run loop spécifique (NSApplication vs RunLoop.main) : la factorisation doit préserver cette distinction.
- Les variables d'état partagées (`displaySettlingUntil`, `pendingDisplayHeal`) doivent rester cohérentes quel que soit le mode.
- Le lock PID (SPEC-011) ne s'applique qu'aux sous-commandes, pas au monolithique : la factorisation ne doit pas casser cette logique.

## Exigences

### Exigences fonctionnelles

**EF-001** Le démarrage de chaque composant (`tiler`, `rail`, `border`, `focus-mouse`, `titlebar-menu`, `target-mode`, `restore-safety`) DOIT être encapsulé dans une fonction de démarrage unique, réutilisable par les deux modes.

**EF-002** Le mode monolithique (`run`) DOIT appeler ces fonctions de démarrage selon les flags `--no-*` (composant actif par défaut, désactivable).

**EF-003** Chaque sous-commande modulaire DOIT appeler la fonction de démarrage du composant correspondant, après acquisition du lock PID (SPEC-011).

**EF-004** Le `displayChangeObserver` et le live observer AX DOIVENT être attachés au composant tiler dans sa fonction de démarrage unique, donc actifs dans les deux modes sans duplication.

**EF-005** Aucune duplication de logique de setup ne DOIT subsister entre le `case "run"` et les sous-commandes pour un même composant.

**EF-006** Le comportement observable (events émis, fenêtres gérées, réactivité) DOIT être strictement identique avant/après le refactor dans les deux modes.

### Critères de succès mesurables

**SC-001** Le nombre de blocs de setup dupliqués pour les composants dans `roadied/main.swift` passe de N (actuel) à 0 (mesure : revue de code + grep des instanciations de contrôleurs).

**SC-002** 100% des tests Swift existants passent après le refactor (mesure : `swift test` = 428+).

**SC-003** `roadie query components` après `Scripts/start-modular` retourne les 7 composants, identique à avant SPEC-012 (mesure : diff).

**SC-004** Le tiler émet des `live_tick` (~15-80ms) et `display-change-heal` dans les DEUX modes (mesure : events.jsonl après ouverture fenêtre + changement écran).

### Non-objectifs

- Aucune nouvelle fonctionnalité utilisateur (c'est un refactor interne).
- Pas de changement du moteur de layout (réservé à SPEC-013).
- Pas de suppression d'un des deux modes : les deux sont conservés.
- Pas de changement du format des PID files ni du protocole SPEC-011.

## Dépendances avec specs existantes

- **SPEC-011** (Atomic Components) : SPEC-012 refactore le code introduit par SPEC-011 sans changer son comportement. Prérequis direct.
- **SPEC-013** (Persistent BSP Tree) : SPEC-012 est un **prérequis** de SPEC-013. L'arbre BSP persistant sera construit sur cette base de lifecycle unifiée pour éviter de réintroduire de la divergence.

## Checklist de validation

- [ ] Les scénarios couvrent parité, source unique, non-régression
- [ ] Les exigences sont mesurables
- [ ] Les critères de succès ont des seuils précis
- [ ] Les non-objectifs cadrent le scope (refactor pur, pas de feature)
- [ ] La dépendance avec SPEC-011 (amont) et SPEC-013 (aval) est documentée
