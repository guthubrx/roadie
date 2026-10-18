# Audit de reutilisation de l'existant - 047 fenêtre flottante

## Decision

Statut: PASS
Date: 2026-10-18
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/047-fenetre-flottante

Conclusion courte: le plan étend l'épinglage existant au lieu de créer un état
de flottement parallèle. Aucun nouveau fichier source, service, type persistant
ni dépendance.

## Items du plan

| Item | Catégorie | Existant | Classement | Décision |
|---|---|---|---|---|
| Portée `stage` | type persistant | `WindowPinScope` (`StageStore.swift:952`) | POTENTIELLEMENT SIMILAIRE | REUTILISER : ajout d'un cas |
| Visibilité par stage | règle | `PersistentWindowPin.visibility(in:)` (`StageStore.swift:990-1031`) | DUPLICATION EVITEE | REUTILISER |
| Sortie de l'arbre | règle | adhésion si `pin == nil` (`DaemonSnapshot.swift:642`) | OK | REUTILISER |
| Restauration du cadre | règle | `pinRestoreCommands` (`LayoutMaintainer.swift:2262`) | OK | REUTILISER |
| Bascule | action | `setPin` / `removePin` (`WindowContextActions.swift:164-215`) | POTENTIELLEMENT SIMILAIRE | REUTILISER : nouvelle méthode qui les appelle |
| Commande `toggle floating` | CLI | spec déclarée non implémentée (`CLICommandRouter.swift:243, 731`) | OK | ETENDRE |
| Entrée de menu | UI | `addWindowItems` (`TitlebarContextMenuController.swift:368-405`) | OK | ETENDRE |
| Règle `action.floating` | config | `DaemonSnapshot.applyTilingPolicy` | POTENTIELLEMENT SIMILAIRE | NON RETENU : fenêtre visible sur toutes les stages, voir research.md |

## Memoire projet

- Constitution XIX : pas d'état parallèle ; extension d'un mécanisme testé.
- Article XVIII : visibilité O(1), bascule O(n).
- AGENTS.md : docs FR/EN et changelog alignés.

## Gate avant tasks

- [x] Chaque item a une ligne de résultat.
- [x] Aucune duplication évidente non arbitrée.
- [x] Aucun refactor du plan requis.
