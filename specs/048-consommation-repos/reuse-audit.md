# Audit de reutilisation de l'existant - 048 consommation au repos

## Decision

Statut: PASS
Date: 2026-10-18
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/specs/048-consommation-repos

Conclusion courte: toutes les interventions étendent des types existants. Un seul
élément nouveau, la génération d'observation, n'a pas d'équivalent utilisable.

## Items du plan

| Item | Existant | Classement | Décision |
|---|---|---|---|
| Génération d'observation | `PlacementGeneration` (`Sources/RoadieAX/WrittenFrameRegistry.swift:207`) | POTENTIELLEMENT SIMILAIRE | CREER : `PlacementGeneration` ne bouge qu'aux commandes et arbitre les écritures ; l'incrémenter à chaque événement changerait cet arbitrage. Compteur ajouté dans `SnapshotProcessState` existant. |
| Révision de publication | `SnapshotProcessState.revision` (`DaemonSnapshot.swift`) | POTENTIELLEMENT SIMILAIRE | NON RETENU : elle compte les publications, pas les changements observés. |
| Réutilisation du relevé | `SnapshotProcessState.recentSnapshot` | OK | ETENDRE |
| Cache SCWindow | `RailThumbnailStore` | OK | ETENDRE |
| Statut d'enregistrement | `TargetRecordingStatusStore.activeStatus`, watcher `recording_status` (session 040) | OK | REUTILISER |
| Vignettes en place | `StageCardView.setReorderPreviewPosition` (mise à jour en place existante) | OK | ETENDRE sur ce modèle |

## Memoire projet

- ADR 013 : durées de validité conservées pour les commandes ; extension conditionnelle
  aux lecteurs documentée par l'ADR 015.
- Constitution XXII : mesure avant/après obligatoire.

## Gate avant tasks

- [x] Chaque item a une ligne de résultat.
- [x] Aucune duplication évidente non arbitrée.
- [x] Aucun refactor du plan requis.
