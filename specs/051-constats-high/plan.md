# Plan - 051 Constats HIGH restants

Base : branche `session-048-consommation-repos`. Aucun nouveau fichier source ni dépendance.

| Id | Intervention | Fichier |
|---|---|---|
| A-02 | Index AX du relevé précédent réutilisé s'il couvre toutes les fenêtres visibles de l'application ; sinon énumération | `Sources/RoadieAX/SystemSnapshotProvider.swift` |
| A-03 | Identifiant d'application mémorisé par processus pendant un relevé | idem |
| A-04 | Chemin des règles générées mémorisé par chemin de configuration | `Sources/RoadieDaemon/ConfigReloadService.swift` |
| A-05 | Minuterie focus-souris à 1 s si l'option est désactivée, 0,1 s sinon, ajustée à chaud | `Sources/RoadieDaemon/FocusFollowsMouseController.swift` |
| B-01 | Réconciliation d'une copie sans verrou ; transaction seulement si l'état change, avec réutilisation du résultat si le fichier n'a pas bougé | `Sources/RoadieDaemon/DaemonSnapshot.swift` |
| C-05 | Pré-filtre du clic sur les bandes de titre gérées du dernier cycle avant tout contexte de glisser | `Sources/RoadieDaemon/RailController.swift`, `DropPreviewController.swift` |
| C-06 | Membres d'un rail replié exclus des captures | `RailController.swift`, `RailPanel.swift` |
| D-03 | Commandes en arbre : `applyTreeScope(using: snapshot)` | `Sources/RoadieDaemon/WindowCommands.swift` |
| D-02 | Non modifié : décision d'architecture (ADR 013), recommandation dans `research.md` | - |

Complexité : A-02 O(k) par application (k fenêtres demandées) au lieu d'une énumération AX ;
A-03 O(1) par fenêtre ; C-05 O(w) ; B-01 une comparaison d'état, déjà faite par la transaction.
