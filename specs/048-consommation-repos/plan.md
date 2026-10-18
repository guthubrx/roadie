# Plan - 048 Consommation au repos

Swift 6, AppKit, Swift Testing. Aucun nouveau fichier source ni dépendance.

1. A-01 `Sources/RoadieDaemon/DaemonSnapshot.swift` : `SnapshotProcessState` garde une
   génération d'observation globale (`noteObservationChange()`), mémorisée à la
   publication. `recentSnapshot(..., allowQuietReuse:)` accepte un relevé plus ancien que
   `maxAge` si la génération est inchangée et l'âge inférieur au plafond `quietReuseCap`.
   `readerSnapshot` passe `allowQuietReuse: true` ; `sharedSnapshot` garde la règle des 150 ms.
   Le plafond vaut 0 tant que le tiler ne l'active pas (`enableQuietReaderReuse`, événements en
   direct seulement) ; il est égal au filet du tiler, 2 s par défaut (revue du plan, ADR 015).
   L'acquisition lecteur capture la génération à son départ.
   `Sources/RoadieDaemon/TickScheduler.swift` : `request` appelle `noteObservationChange()`
   pour toute demande hors filet de sécurité.
2. C-01 `Sources/RoadieDaemon/RailThumbnailStore.swift` : cache `SCWindow` par identifiant,
   énumération si un identifiant manque ou après échec ; dimension depuis le cadre du membre.
3. C-02 `Sources/RoadieDaemon/RailController.swift` : statut d'enregistrement mémorisé,
   rechargé sur `recording_status`, vivacité vérifiée à chaque tick.
4. C-03 `RailController.swift`, `RailPanel.swift`, `StageCardView.swift` : signature de
   structure et signature de vignettes séparées ; `RailPanel.refreshThumbnails` met à jour
   les cartes existantes.
5. Tests ciblés, suite complète, mesure après dans les mêmes conditions, ADR 015.

Complexité : réutilisation O(1) ; cache SCWindow O(k) par lot (k fenêtres demandées) ;
mise à jour des vignettes O(c × m) (cartes × membres), sans recréation de vues.

Retour arrière : chaque point est indépendant et réversible commit par commit.
