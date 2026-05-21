# Spécification de fonctionnalité : Composants Roadie atomiques

**Branche** : `011-atomic-components`
**Créé le** : 2026-05-10
**Statut** : Prêt pour planification
**Entrée utilisateur** : "Je veux qu'on rende tout ça atomique, je sais pas si c'est le bon mot, pour qu'on puisse lancer les choses indépendamment les unes des autres"
**Contexte conversation** : Suite directe de l'audit SPEC-002 et de l'observation que `RailController`, `BorderController`, `FocusFollowsMouseController`, `TitlebarContextMenuController`, `TargetModeRuntimeController` et `LayoutMaintainer` sont logiquement indépendants mais couplés dans le binaire `roadied`.

## Scénarios utilisateur et tests

### Scénario 1 — Lancer uniquement le rail sans le tiler (Priorité : P1)

Un utilisateur a un setup où le tiling automatique le gêne (par exemple il préfère du floating), mais il veut garder le rail latéral comme navigation visuelle entre stages/desktops. Aujourd'hui il doit lancer `roadied run --yes` qui démarre aussi `LayoutMaintainer`, donc le tiler bouge ses fenêtres.

**Pourquoi cette priorité** : c'est le cas d'usage le plus demandé après l'audit SPEC-002. Sans cette atomicité, l'utilisateur est obligé de tout prendre ou tout laisser.

**Test indépendant** : démarrer `roadied` en mode rail seul, ouvrir une nouvelle fenêtre, vérifier qu'aucun re-layout automatique n'est appliqué et que le rail reste fonctionnel (clics, vignettes, drag-and-drop entre stages).

**Scénarios d'acceptation** :

1. **Étant donné** que l'utilisateur veut le rail sans tiler, **Quand** il lance la commande dédiée, **Alors** le rail apparaît et reste réactif sans qu'aucune fenêtre ne soit déplacée par `LayoutMaintainer`.
2. **Étant donné** le rail seul est en cours d'exécution, **Quand** l'utilisateur clique sur un stage différent, **Alors** le changement de stage applique le hide/show des fenêtres (cette opération est synchrone côté CLI, déjà documentée par SPEC-002).
3. **Étant donné** le rail seul est en cours, **Quand** une nouvelle fenêtre apparaît dans le stage courant, **Alors** elle n'est **pas** re-positionnée automatiquement (comportement attendu : pas de tiler).

---

### Scénario 2 — Désactiver un composant précis du daemon complet (Priorité : P1)

Un utilisateur lance `roadied` complet mais veut désactiver un composant précis (par exemple le `FocusFollowsMouseController` qui le gêne, ou le `TitlebarContextMenuController` qui interfère avec une autre app). Aujourd'hui il n'a que les flags `--no-rail` et `--no-restore-safety`.

**Pourquoi cette priorité** : symétrie avec scénario 1, granularité fine sans changer de binaire.

**Test indépendant** : lancer `roadied run --yes --no-focus-mouse --no-titlebar-menu`, vérifier dans les logs qu'aucun monitor associé n'est installé, vérifier que les autres composants démarrent normalement.

**Scénarios d'acceptation** :

1. **Étant donné** l'utilisateur veut désactiver un composant, **Quand** il passe le flag `--no-<composant>` correspondant, **Alors** ce composant n'est pas instancié et n'apparaît pas dans les logs de démarrage.
2. **Étant donné** plusieurs composants sont désactivés, **Quand** `roadied` démarre, **Alors** les composants restants démarrent sans erreur et ne dépendent pas des composants désactivés.
3. **Étant donné** un flag inconnu est passé, **Quand** `roadied` démarre, **Alors** un message d'erreur clair est émis et le daemon refuse de démarrer.

---

### Scénario 3 — Lancer un composant unique en sous-process (Priorité : P2)

Un utilisateur power-user veut superviser chaque composant indépendamment (par exemple via tmux ou launchd) pour avoir des journaux séparés et un cycle de vie indépendant. Il veut pouvoir relancer le rail sans relancer le tiler.

**Pourquoi cette priorité** : ergonomie ops avancée, c'est le mode "unix-philosophy" naturel après la décomposition. Possiblement la fondation pour des intégrations futures (homebrew services, launchd plists par composant).

**Test indépendant** : lancer `roadied tiler --yes` dans une session tmux, `roadied rail` dans une autre, vérifier que chacun s'exécute indépendamment, qu'on peut tuer l'un sans affecter l'autre, et que le rail continue à pouvoir changer de stage (via le CLI ponctuel).

**Scénarios d'acceptation** :

1. **Étant donné** plusieurs composants sont lancés en sous-processus séparés, **Quand** l'un est tué, **Alors** les autres continuent sans crash ni log d'erreur.
2. **Étant donné** un composant seul est en cours, **Quand** une opération qui le concerne est déclenchée, **Alors** elle s'exécute normalement (rail seul → clic change de stage ; tiler seul → re-layout automatique des nouvelles fenêtres).
3. **Étant donné** un composant a besoin d'un état partagé (`~/.roadies/stages.json`, `events.jsonl`), **Quand** plusieurs composants sont lancés en parallèle, **Alors** les écritures restent cohérentes (verrou EventLog SPEC-002 déjà en place).

---

### Scénario 4 — Observer quels composants sont actifs (Priorité : P3)

Un utilisateur ou un script veut savoir quels composants sont actifs à un instant donné, pour piloter des intégrations conditionnelles (ex : sketchybar n'affiche pas l'icône stage si tiler désactivé).

**Pourquoi cette priorité** : facilite la composition avec l'écosystème externe (sketchybar, BetterTouchTool, scripts utilisateur).

**Test indépendant** : interroger l'état via `roadie query components` ou équivalent, vérifier que la liste reflète les composants réellement instanciés.

**Scénarios d'acceptation** :

1. **Étant donné** plusieurs composants tournent, **Quand** un outil externe interroge l'état, **Alors** la liste retournée est stable, datée et exhaustive.
2. **Étant donné** un composant n'est pas démarré, **Quand** l'outil interroge l'état, **Alors** ce composant apparaît avec un statut `inactive` ou est absent de la liste avec une raison claire.

### Cas limites

- Un composant nécessite l'autorisation Accessibility, l'autorisation est refusée : démarrage doit échouer proprement avec un message non-anxiogène, et les autres composants démarrent quand même si possible.
- Deux instances de `roadied tiler` lancées simultanément : la deuxième doit détecter le doublon et refuser de démarrer (lock file PID).
- Un composant est tué brutalement (SIGKILL) : les autres ne doivent pas s'arrêter en cascade. Les ressources partagées (event log, state file) restent cohérentes grâce au verrou SPEC-002.
- Le binaire `roadied` est invoqué sans sous-commande ni mode legacy `run` : afficher l'aide claire avec tous les modes disponibles.
- L'utilisateur passe simultanément `--no-tiler` et lance `roadied tiler` : refus avec message explicatif.

## Exigences

### Exigences fonctionnelles

**EF-001** Le binaire `roadied` DOIT supporter le mode legacy `roadied run --yes` qui démarre tous les composants par défaut (rétro-compatibilité stricte avec scripts existants `Scripts/start`).

**EF-002** Le mode `roadied run` DOIT accepter un flag `--no-<composant>` pour chacun des composants suivants : `--no-rail` (déjà), `--no-restore-safety` (déjà), `--no-tiler`, `--no-border`, `--no-focus-mouse`, `--no-titlebar-menu`, `--no-target-mode`.

**EF-003** Le binaire `roadied` DOIT supporter des sous-commandes dédiées pour lancer un composant unique : `roadied tiler --yes`, `roadied rail`, `roadied border`, `roadied focus-mouse`, `roadied titlebar-menu`, `roadied target-mode`, `roadied restore-safety`.

**EF-004** Chaque sous-commande composant DOIT être autonome : démarrer son composant unique, son `RunLoop` (NSApplication ou Foundation selon besoin), et ne pas instancier les autres composants.

**EF-005** Chaque sous-commande composant DOIT poser un lock PID dans `~/.roadies/<composant>.pid` au démarrage et refuser le démarrage si un PID actif est déjà détecté.

**EF-006** Les composants partagent l'état système via les fichiers existants (`~/.roadies/stages.json`, `~/.roadies/events.jsonl`, `~/.roadies/intent.json`) avec les verrous EventLog déjà en place (SPEC-002).

**EF-007** Une nouvelle commande CLI `roadie query components` DOIT retourner la liste des composants actifs avec leur PID, leur timestamp de démarrage et leur statut.

**EF-008** Les flags inconnus ou conflictuels DOIVENT produire un message d'erreur explicite et un exit code différent de 0.

**EF-009** Le script `Scripts/start` DOIT continuer à fonctionner sans modification (utilise `roadied run --yes`).

### Critères de succès mesurables

**SC-001** Lancer `roadied rail` (sans tiler) consomme moins de 50 % de la RAM utilisée par `roadied run --yes` complet (mesure : `ps -o rss=` 30 secondes après démarrage).

**SC-002** Le démarrage de tous les composants en sous-process indépendants prend moins de 5 secondes au total (mesure : entre `Scripts/start-modular` et premier event `daemon.ready` sur chaque composant).

**SC-003** Tuer un composant via SIGTERM ne provoque aucun crash ni log d'erreur dans les autres composants pendant 30 secondes (mesure : `tail -f .roadies/*.stderr.log` sur 30 s).

**SC-004** La rétro-compatibilité `roadied run --yes` lance exactement les mêmes composants qu'aujourd'hui (mesure : diff de la liste des composants démarrés via `roadie query components` avant/après SPEC-011).

**SC-005** 100 % des tests Swift existants restent verts après le refactor (mesure : `swift test` = 252/252).

### Non-objectifs (out of scope)

- Restructuration en N binaires séparés (`roadied-tiler`, `roadied-rail`...) : on reste sur un binaire unique `roadied` avec sous-commandes. C'est suffisant pour l'atomicité et évite la complexité de packaging.
- Communication inter-composants via IPC dédié (Unix socket, XPC) : on garde les fichiers partagés actuels avec verrou EventLog.
- Plists launchd séparés par composant : peut être un complément futur, hors scope.
- Hot-reload d'un composant sans redémarrage : hors scope.

## Dépendances avec specs existantes

- **SPEC-002** (Roadie Ecosystem Upgrade) : prérequis fonctionnel. Le verrou EventLog ajouté en SPEC-002 (audit cycle 1, finding R2) est nécessaire pour permettre des écritures concurrentes par plusieurs composants. Sans ce verrou, plusieurs `EventLog().append()` simultanés depuis des process séparés corromperaient `events.jsonl`.
- **SPEC-009** (Roadie Target Mode) : impact d'extension. `TargetModeRuntimeController` doit pouvoir être désactivé via flag et lancé en sous-commande dédiée.
- Aucune nouvelle dépendance externe.

## Checklist de validation

- [ ] Les scénarios couvrent les 3 modes (legacy, flags, sous-commandes)
- [ ] Les exigences fonctionnelles sont mesurables et testables
- [ ] Les critères de succès ont des seuils précis
- [ ] Les non-objectifs sont explicites pour cadrer le scope
- [ ] Les dépendances avec SPEC-002 et SPEC-009 sont documentées
