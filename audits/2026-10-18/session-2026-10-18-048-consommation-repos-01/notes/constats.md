# Constats - révision 0 (avant correction)

Auditeur : Claude, independent=false. Aucune revue indépendante. Preuves : lecture de source
(extraits conservés dans `avant-correction/`), aucune reproduction runtime (redémarrage interdit).

## F1 - LOW - Statut d'enregistrement mémorisé conservé après l'arrêt du watcher

- Fichier : `Sources/RoadieDaemon/RailController.swift`, `RailController.stop()` (l. 104-136 en r0).
- Cause : C-02 mémorise le statut (`recordingStatusCache`, `recordingStatusDirty`) parce que le
  watcher `recording_status` signale chaque changement. `stop()` arrête ce watcher (l. 117) mais ne
  remet pas `recordingStatusDirty` à vrai. `RailFileWatcher.start()` prend l'empreinte du fichier au
  réarmement (`RailFileWatchers.swift:27`) : un changement survenu pendant l'arrêt n'est jamais signalé.
- Ordonnancement : statut nil mémorisé, `stop()`, un enregistrement démarre (écriture atomique),
  `start()` ; au tick suivant `recordingStatus(cached: nil, dirty: false)` rend nil sans lecture :
  l'indicateur reste absent pendant tout l'enregistrement.
- Atteignabilité : aujourd'hui `stop()` n'est appelé qu'à l'arrêt du daemon (`main.swift:184`). Le
  contrat documenté de `stop()` dit « `start()` peut ensuite être rappelé ». Défaut latent, régression
  par rapport à la lecture par tick d'avant 048. Sévérité LOW.
- Correction (non ambiguë, dans le diff 048) : dans `stop()`, `recordingStatusCache = nil` et
  `recordingStatusDirty = true`, sur le modèle de `lastThumbnailSignatures.removeAll()` ajouté par 048.

## F2 - MEDIUM - R3 partielle : la minuterie du rail relit encore deux fichiers inchangés

- Fichier : `Sources/RoadieDaemon/RailController.swift`, `renderPanels` (l. 929 et 933 en r0).
- Exigence R3 : « Une minuterie du rail sans changement d'état ne fait ni relevé complet supplémentaire
  ni relecture de fichier inchangé. »
- Observé : chaque tick (1 s) appelle `store.state()` (`StageStore.swift:177`, `JSONPersistence.load`
  sans cache : lecture et décodage de `~/.roadies/stages.json`, 58 084 octets le 18/10) et
  `railRuntimeStateStore.load()` (`RailRuntimeState.swift:41`, `rail.json`, 498 octets).
  `RailSettings.load` est, lui, déjà mis en cache par empreinte (`RailSettings.swift:131`).
- Seule la relecture de `recording.json` a été supprimée (C-02). `validation.md` ne signale pas ce reste.
- Coût non mesuré. Le CPU au repos a déjà baissé de 80 % ; le reste est une violation de l'exigence,
  pas une panne.
- Non corrigé : un cache par empreinte de `stages.json` change la sémantique de lecture d'un état partagé
  entre processus (mode modulaire) et exige une mesure (constitution XXII). Décision attendue :
  mettre en cache par empreinte (modèle `RailSettingsCache`) ou réduire le texte de R3.

## F3 - LOW - Plan, tâches et recherche décrivent un plafond de 1 s et une API absente

- Fichier : `specs/048-consommation-repos/plan.md` l. 7-9 (`quietMaxAge`, « 1 s ») ; `tasks.md` T002 ;
  `research.md` l. 35.
- Code : `recentSnapshot(..., allowQuietReuse:)`, plafond `quietReuseCap` = filet du tiler (2 s par
  défaut), activé seulement avec les événements en direct (`main.swift:425`). ADR 015 et validation.md
  décrivent correctement le choix final.
- Correction : alignement du texte des trois artefacts, historique conservé (mention « après revue »).

## F4 - MEDIUM - Variante hors diff : les poignées relisent `stages.json` toutes les 150 ms

- Fichier : `Sources/RoadieDaemon/DividerResizeRuntime.swift`, `update(snapshot:)` l. 167 ; minuterie
  0,15 s l. 37 ; `refresh` l. 87.
- Même mécanisme que F2 : lecteur périodique qui décode le fichier d'état sans changement, environ
  6,7 fois par seconde quand les poignées sont actives. Antérieur à 048 (fichier hors diff), découvert
  par la recherche de variantes sur les lecteurs de `readerSnapshot`.
- Non corrigé : hors périmètre du diff ; `snapshot.state` est déjà disponible mais le choix d'une lecture
  fraîche peut être intentionnel (arbre, générations). Recommandation pour la session 051.
