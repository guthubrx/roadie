# Feature Specification: Stages scopées par (display × desktop)

**Feature Branch**: `018-stages-per-display`
**Status**: Implemented (V1 livré 2026-05-03 + 6 fixes post-livraison même jour)
**Created**: 2026-05-02
**Dependencies**: SPEC-002 (Stage Manager), SPEC-011 (Virtual Desktops), SPEC-012 (Multi-display), SPEC-013 (Desktop-per-display)
**Blocks**: SPEC-014 (Stage Rail UI — bloquée tant que les stages restent globales)

## Vision

Aujourd'hui, le StageManager du daemon `roadied` indexe ses stages par un identifiant simple (`stageID`). Cet identifiant est **global** : si l'utilisateur crée "Stage 2" alors qu'il travaille sur Display 1, la même "Stage 2" est visible et manipulable depuis Display 2. Or conceptuellement, dans un setup multi-display avec mode `[desktops] mode = "per_display"` (cf SPEC-013), chaque écran possède son propre desktop courant indépendant. Il en découle que les stages devraient elles aussi être strictement scopées au tuple `(display, desktop)`, exactement comme un classeur physique posé sur un bureau précis.

Cette spec aligne le modèle des stages sur celui des desktops (SPEC-013), pour donner à l'utilisateur le sentiment que **chaque écran est un poste de travail autonome**. Elle débloque le rail UI (SPEC-014) qui aujourd'hui ne peut pas filtrer correctement les cartes par écran.

## Principes architecturaux non-négociables

1. **Compat ascendante stricte en mode `global`.** Si l'utilisateur a configuré `[desktops] mode = "global"` (ou laisse le défaut V1 si V1 = global), le comportement reste flat exactement comme avant cette spec. Aucune migration forcée, aucune surprise pour l'utilisateur mono-display ou qui préfère le modèle simple.

2. **Scope implicite via le focus.** En mode `per_display`, l'utilisateur n'a JAMAIS à passer un argument `--display` ou `--desktop` sur la CLI. Le scope est résolu côté daemon depuis :
   - la position du curseur (priorité 1, pattern yabai/AeroSpace) ;
   - la frontmost window (priorité 2) ;
   - le primary display (priorité 3, fallback ultime).

3. **Migration silencieuse au premier boot V2.** Les stages existantes "globales" sur disque sont automatiquement assignées au tuple `(mainDisplayUUID, defaultDesktop=1)` sans intervention utilisateur, sans perte. Backup automatique du `stages/` original avant migration.

4. **Aucune fuite IPC dans les commandes existantes.** Les contrats IPC publics (`stage.list`, `stage.assign`, etc.) restent le même nom de commande et le même format de retour, juste filtré par scope implicite. L'utilisateur power-user qui veut explicitement viser un autre display peut passer un override via `--display <uuid|index> --desktop <id>` (NEW V2, optionnel).

## User Scenarios & Testing

### User Story 1 — Stages indépendantes par écran (P1, MVP)

**As an** utilisateur multi-display en mode `per_display`,
**I want** que mes stages créées sur Display 1 ne polluent pas la liste des stages que je vois sur Display 2,
**So that** chaque écran fonctionne comme un espace de travail isolé conformément au modèle introduit par SPEC-013.

**Acceptance scenarios** :
1. Démarrer roadied avec 2 écrans, mode `per_display`, current desktop = 1 sur les deux. Créer "Stage 2" sur Display 1 (curseur sur Display 1 + `roadie stage assign 2`). Déplacer la souris sur Display 2 et lancer `roadie stage list` → la sortie ne doit PAS contenir "Stage 2" (uniquement la stage 1 par défaut).
2. Créer une "Stage 2" différente sur Display 2 (curseur sur Display 2). Les deux "Stage 2" coexistent dans le daemon mais sous tuples différents `(D1, 1, 2)` et `(D2, 1, 2)`. `roadie stage list` retourne uniquement celles du scope courant.
3. Switcher de desktop sur Display 1 (Ctrl+→) → la liste des stages affichée pour Display 1 change vers celles du desktop 2 ; la liste pour Display 2 reste inchangée.

### User Story 2 — Migration silencieuse depuis V1 (P1, MVP)

**As an** utilisateur existant qui avait des stages V1 (globales) avant l'upgrade,
**I want** que mes stages soient préservées et placées sur mon écran principal au premier lancement V2,
**So that** je ne perde aucun travail et puisse continuer à utiliser le système sans intervention.

**Acceptance scenarios** :
1. Avant upgrade : `~/.config/roadies/stages/2.toml` existe avec une stage nommée "Code". Premier boot daemon V2 → un backup `~/.config/roadies/stages.v1.bak/` contient l'ancien layout, et `~/.config/roadies/stages/<mainDisplayUUID>/1/2.toml` contient maintenant la même stage "Code".
2. `roadie stage list` (curseur sur n'importe quel écran si mode global) ou (curseur sur écran principal si mode per_display) retourne "Code" → l'utilisateur récupère exactement son inventaire.
3. Si le boot V2 plante avant la fin de la migration, le `stages.v1.bak/` permet une recovery manuelle (l'utilisateur peut renommer pour restaurer V1).

### User Story 3 — Mode `global` préservé (P1, MVP)

**As an** utilisateur mono-display ou qui préfère un namespace global,
**I want** que `[desktops] mode = "global"` continue à exposer les stages comme avant cette spec, partagées entre tous les écrans,
**So that** je ne sois pas forcé d'adopter un modèle plus complexe contre mon gré.

**Acceptance scenarios** :
1. Config TOML : `[desktops] mode = "global"`. Comportement identique pré-018 : `roadie stage assign 2` puis switch d'écran → la "Stage 2" reste visible. Aucune indexation par display.
2. Persistance : les fichiers `~/.config/roadies/stages/<id>.toml` flat sont relus tels quels (pas de migration appliquée, pas de tuple display).
3. Switch de mode à chaud (`roadie daemon reload` après changement TOML) — les stages se réindexent ou s'aplatissent selon le nouveau mode (best effort, documenté dans le quickstart).

### User Story 4 — Override explicite pour scripts power-user (P2)

**As a** scripteur (BTT, SketchyBar, automation),
**I want** pouvoir explicitement cibler une stage sur un display spécifique sans bouger le curseur,
**So that** je puisse écrire des macros qui fonctionnent sans dépendance au pointeur.

**Acceptance scenarios** :
1. `roadie stage list --display 2 --desktop 1` retourne uniquement les stages de l'écran 2 desktop 1, indépendamment de la position du curseur.
2. `roadie stage assign 3 --display 2 --desktop 1` crée la stage 3 sur ce tuple précis (lazy create).
3. Sélecteur display accepté : index 1-N (ordre `roadie display list`), ou UUID natif.

### User Story 5 — Cohérence avec le rail UI (P1, MVP)

**As an** utilisateur du rail (SPEC-014),
**I want** que chaque panel rail (un par écran en mode `per_display`) affiche STRICTEMENT les stages de son écran et de son desktop courant,
**So that** je ne vois pas la liste polluée par les stages d'autres écrans.

**Acceptance scenarios** :
1. Avec rail lancé sur 2 écrans, créer une stage sur Display 1 → seul le panel rail de Display 1 la montre dans son fade-in.
2. Switcher de desktop sur Display 2 (Ctrl+←) → seul le panel rail de Display 2 met à jour sa liste (reçoit l'event `desktop_changed` avec `display_id`).
3. Drag-drop chip d'un stage Display 1 vers carte Display 2 → reportée hors-scope V1, doc claire sur cette limitation.

## Functional Requirements

### Modèle de données

- **FR-001** : `StageManager` indexe ses stages par tuple `StageScope = (displayUUID: String, desktopID: Int, stageID: StageID)`. La table interne `stages: [StageScope: Stage]` remplace `stages: [StageID: Stage]`.
- **FR-002** : Chaque `Stage` reste un struct immuable avec `id`, `displayName`, `memberWindows`, `savedRect`, etc. — schéma TOML inchangé sur disque.
- **FR-003** : Le daemon expose une property publique `currentScope: StageScope` calculée à chaque commande, dérivée de la position du curseur (priorité 1) → frontmost (priorité 2) → primary display (priorité 3).

### Commandes IPC

- **FR-004** : `stage.list` retourne par défaut les stages du `currentScope` uniquement. Les stages globales d'autres écrans ne sont JAMAIS dans cette réponse.
- **FR-005** : `stage.assign <id>`, `stage.switch <id>`, `stage.create <id> <name>`, `stage.delete <id>`, `stage.rename <id> <name>` opèrent sur le `currentScope`. Une stage `2` créée alors que le scope est `(D1, 1)` n'existe pas pour le scope `(D2, 1)`.
- **FR-006** : Toutes les commandes ci-dessus acceptent un argument optionnel `--display <selector>` et `--desktop <id>` qui override le scope inféré. `selector` accepte index numérique 1-N ou UUID.
- **FR-007** : La réponse de `stage.list` inclut désormais les champs `display_uuid`, `display_index`, `desktop_id`, `scope_inferred_from` (`"cursor"|"frontmost"|"primary"`) pour transparence côté client.

### Persistance

- **FR-008** : En mode `per_display`, les fichiers TOML sont organisés en `~/.config/roadies/stages/<displayUUID>/<desktopID>/<stageID>.toml`. Le `displayUUID` est celui retourné par `CGDisplayCreateUUIDFromDisplayID` (stable cross-reboot).
- **FR-009** : En mode `global`, l'arborescence reste plate : `~/.config/roadies/stages/<stageID>.toml` (compat stricte SPEC-002/V1).
- **FR-010** : Le daemon détecte le mode au boot et choisit la bonne stratégie de persistance. Hot-switch de mode à chaud nécessite `roadie daemon reload` et déclenche une re-index/re-flatten best effort (documenté).

### Migration V1 → V2

- **FR-011** : Au premier boot V2, si `~/.config/roadies/stages/<id>.toml` (flat) existe ET le mode est `per_display`, le daemon :
  1. Crée un backup `~/.config/roadies/stages.v1.bak/` (timestamp horodaté en cas de re-migration accidentelle).
  2. Crée le dossier `~/.config/roadies/stages/<mainDisplayUUID>/1/`.
  3. Déplace tous les `<id>.toml` flat vers ce dossier.
  4. Log `migration_v1_to_v2` event sur EventBus.
- **FR-012** : Idempotent : si `stages.v1.bak/` existe déjà, la migration n'est PAS re-déclenchée (prévient les ré-overwrites en cas de boot multiples).
- **FR-013** : Si la migration plante (disque plein, permission refusée), le daemon log un erreur structurée, n'active PAS le mode V2 (reste sur V1 flat le temps de l'investigation), et expose `daemon.status` avec un flag `migration_pending: true`.

### Multi-display & desktop

- **FR-014** : Sur changement de desktop (event `desktop_changed`), le `currentScope.desktopID` est mis à jour automatiquement pour le display concerné. Aucun changement côté client ; `stage.list` retourne implicitement les bonnes stages.
- **FR-015** : Sur débranchement d'un écran (event `display_removed`), les stages du `displayUUID` retiré sont préservées sur disque (pas supprimées). Au rebranchement (matching par UUID stable), elles sont restaurées.
- **FR-016** : Sur ajout d'un nouvel écran (`display_added`), aucune stage n'est créée automatiquement (l'écran démarre sans stage personnalisée, juste la stage default 1 implicite à la première interaction).

### Events & observabilité

- **FR-017** : Les events `stage_changed`, `stage_renamed`, `stage_created`, `stage_deleted` (existants ou nouveaux) incluent désormais les champs `display_uuid` et `desktop_id` dans leur payload.
- **FR-018** : Nouvel event `migration_v1_to_v2` émis au premier boot V2 avec champs `migrated_count`, `backup_path`, `target_display_uuid`.
- **FR-019** : `daemon.status` expose `stages_mode: "per_display"|"global"` et `current_scope: {display_uuid, desktop_id}` pour debug.

### Compat & gracieuse

- **FR-020** : Si `currentScope.displayUUID` est vide (write API échoue à résoudre l'écran sous le curseur, cas de l'écran branché à chaud), fallback sur primary display sans erreur.
- **FR-021** : La création/suppression d'une stage hors mode `per_display` ne touche pas l'arborescence per-display (et inversement) — les deux modes sont strictement étanches.

## Success Criteria

- **SC-001** : En mode `per_display` avec 2 écrans, créer "Stage 2" sur Display 1 puis lancer `roadie stage list` avec curseur sur Display 2 retourne UNIQUEMENT la stage 1 par défaut, jamais "Stage 2".
- **SC-002** : Migration V1 → V2 préserve 100% des stages existantes (compté par fichier TOML avant/après) en moins de **500 ms** pour 50 stages, sans perte de `displayName` ni de `memberWindows`.
- **SC-003** : En mode `global`, le comportement reste identique à SPEC-002 V1 : 100% des tests de régression SPEC-002 passent sans modification.
- **SC-004** : La résolution de scope (curseur → display) ajoute moins de **5 ms** de latence à toute commande `stage.*` (mesuré au p95).
- **SC-005** : Sur 8 heures d'usage en mode `per_display`, aucune fuite mémoire daemon liée aux index de scope (RSS stable ±10%).
- **SC-006** : Sur débranchement/rebranchement d'écran (matching par UUID), les stages associées sont 100% restaurées sans intervention utilisateur.
- **SC-007** : Le rail UI (SPEC-014) avec cette spec activée affiche STRICTEMENT les stages du scope de chaque panel — vérifié via test manuel multi-display + screenshot.
- **SC-008** : `roadie daemon.status` expose le mode et le scope courant, observable depuis n'importe quel script externe pour debug.

## Key Entities

- **`StageScope`** : tuple `(displayUUID: String, desktopID: Int, stageID: StageID)`. Clé d'indexation interne du StageManager. Sérialisable en string `<uuid>/<desktopID>/<stageID>` pour log et persistance.
- **`Stage`** : inchangée, les attributs `displayName`, `memberWindows`, `savedRect` restent identiques. Le tuple de scope est porté par le conteneur, pas par le Stage lui-même.
- **`StageManagerV2`** : refactor du StageManager qui gère les deux modes (global, per_display) selon la config. Expose `currentScope` et les méthodes scopées.
- **`StagePersistenceV2`** : protocol qui abstrait la stratégie disque (flat ou nested per_display). Implémentations : `FlatStagePersistence` (V1 compat), `NestedStagePersistence` (V2 per_display).
- **`MigrationV1V2`** : composant one-shot qui détecte et exécute la migration au boot. Idempotent.

## Out of Scope (V1 de cette spec)

- **Drag-and-drop cross-display de chips dans le rail** : déplacer une fenêtre d'une stage Display 1 vers une stage Display 2 directement via le rail. Reportée à une SPEC ultérieure (besoin de coordination avec le tiler pour la frame finale).
- **Stages partagées entre desktops** : une stage qui apparaît sur tous les desktops d'un même display (style sticky window). Hors scope V1.
- **UI de gestion des stages depuis le rail** : pas de "Move stage to other display" dans le menu contextuel V1. Le rename/delete reste scopé.
- **Sync iCloud/cross-machine** : la migration est locale, aucune synchronisation cloud des stages.
- **Tests acceptance multi-machine** : V1 testé sur une machine 2 écrans, pas dans un cluster.

## Assumptions

- Le `displayUUID` retourné par `CGDisplayCreateUUIDFromDisplayID` est stable au reboot (cohérent avec SPEC-012).
- Le mode par défaut V1 du projet est `global` (pas de breaking change automatique pour les utilisateurs).
- L'utilisateur en mode `per_display` accepte que renommer un écran (ID hardware identique mais nouveau nom OS) ne change PAS son `displayUUID`.
- La position du curseur est toujours résolvable via `NSEvent.mouseLocation` côté daemon (vrai même sans permission Input Monitoring).

## Risks & Mitigations

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Migration V1 → V2 corrompt les stages | Bas (idempotent + backup) | Élevé (perte de travail) | Backup automatique avant migration, désactivation V2 si migration fail, doc recovery manuelle |
| Curseur hors écran (rare, race condition) | Moyen | Bas | Fallback frontmost, puis primary, jamais d'erreur bloquante |
| Hot-switch de mode global ↔ per_display chaotique | Bas | Moyen | Documentation claire ("redémarrez le daemon, ne switchez pas à chaud en prod") + best effort |
| Confusion utilisateur ("où est passée ma Stage 2 ?") | Moyen | Moyen | `roadie stage list` affiche le scope inféré, message clair "Stages on Display X / Desktop Y" |
| Conflit de `displayUUID` après changement de carte graphique | Bas | Moyen | Le UUID change, les stages sont préservées sur disque mais "orphelines" — l'utilisateur peut les retrouver via `roadie display list` et les ré-assigner manuellement |
| Performance dégradée si beaucoup de displays/desktops/stages | Bas | Bas | Indexation hash O(1), pas de scan linéaire |

## Constitution Check

- [x] Article A : pas de mono-fichier > 200 LOC effectives — refactor StageManager découpé en `StageManagerV2.swift` (orchestration), `StageScope.swift` (clé), `StagePersistenceV2.swift` (protocole + 2 implémentations), `MigrationV1V2.swift` (one-shot)
- [x] Article B : zéro dépendance non justifiée — réutilise `CGDisplayCreateUUIDFromDisplayID` (CoreGraphics), `NSEvent.mouseLocation` (AppKit), TOMLKit (déjà présent)
- [x] Article C' : aucune API privée d'écriture SkyLight — uniquement lecture pour résoudre le display sous le curseur (compatible)
- [x] Article D : pas de `try!`, pas de `print()`, logger structuré JSON-lines
- [x] Article G : plafond LOC à confirmer (cible 600 / plafond 900 LOC pour ce refactor + tests, raisonnable vu le scope)

## Open Questions

(aucune au moment de la rédaction — la description utilisateur est exhaustive, les choix d'archi sont clairement énoncés, la migration est documentée)
