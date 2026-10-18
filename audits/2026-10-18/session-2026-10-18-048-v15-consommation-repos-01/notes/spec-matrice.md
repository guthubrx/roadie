# Matrice des exigences - spec 048 (specs/048-consommation-repos/spec.md, commit ab9b28e9)

| Exigence | Mécanisme attendu | Code / appelants | Tests | Verdict |
|---|---|---|---|---|
| R1 Lecteurs au repos sans relevé complet de plus que le tiler | Réutilisation du relevé publié si aucune observation | `DaemonSnapshot.swift:236-241, 253, 351, 2515` ; `TickScheduler.swift:92` ; `main.swift:372, 425` | Spec048QuietReaderTests (verts) | Implémentée. Limite documentée (ADR 015) : changement sans notification vu jusqu'au filet (2 s) |
| R2 Pas d'énumération SCK à chaque lot si l'ensemble est stable | Cache `SCWindow` par identifiant, attente d'absence 5 s | `RailThumbnailStore.swift` `needsEnumeration`, `capture`, `prune` | `cachedWindowsNeedNoEnumeration`, `absentWindowWaitsBeforeAnotherEnumeration` | Implémentée. Rendu réel avec `SCWindow` mémorisé non observé |
| R3 Minuterie du rail sans changement : ni relevé complet ni relecture de fichier inchangé | Relevé partagé (R1) ; statut mémorisé ; cache par signature | `RailController.swift:900-920, 932-946` ; `JSONPersistence.swift:211-235` | Spec048RecordingStatusTests ; `StatePersistenceTests.swift:66` | Implémentée : `recording.json` mémorisé, `stages.json`/`rail.json` revalidés par `fstat` sans lecture (constat F2 réfuté) |
| R4 Une vignette neuve met à jour sa carte | Signature des vignettes séparée ; mise à jour en place | `RailController.swift:1018-1023` ; `RailPanel.swift:330-336` ; `StageCardView.swift:140-150` | `thumbnailRefreshKeepsTheExistingCards`, `cardRedrawsOnlyWhenAnImageChanges` | Implémentée à l'échelle de l'écran (seules les cartes dont une image change sont redessinées) |
| R5 Comportements conservés | Génération sur focus ; empreinte d'état ; budgets inchangés | `request` sur événements ; `entry.stateStamp == stateStamp` ; budgets et quarantaines inchangés | Suite complète 1 721 tests verts | Implémentée par lecture et tests ; vérification visuelle absente |

Critères de réussite : mesures avant/après conservées dans `mesures/` (relues, non rejouées) ;
suite verte vérifiée par ce run. Hors périmètre respecté : aucun fichier 049-051 dans le diff.
