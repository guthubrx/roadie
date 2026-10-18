# Preuve de contexte - audit V15, session 048 (consommation au repos)

Révision 0 : base d32105c8, modifications locales non commitées, nouveaux fichiers 048.
Auditeur : Claude (même agent que l'orchestration, independent=false). Aucune revue indépendante.

## Biens à protéger

- Exactitude de l'état affiché (bordure, rail, poignées, focus-souris) vis-à-vis des fenêtres réelles.
- Coût CPU au repos du daemon `roadied` (objet de la spec).
- Indicateur d'enregistrement de cibles (signale à l'utilisateur qu'un enregistrement tourne).
- Contrat ADR 013 (durées de validité) amendé par ADR 015.

## Acteurs et points d'entrée

- Tiler (`Sources/roadied/main.swift` `startTilerComponent`) : événements AX (`AXWindowEventObserver`),
  NSWorkspace (`installWorkspaceObservers`), écrans, réveil, réglages, filet périodique 2 s.
  Tous appellent `TickScheduler.request` (lignes 316, 327, 380, 389, 391, 397, 405, 455).
- Lecteurs : `BorderController.swift:71`, `FocusFollowsMouseController.swift:52`,
  `DividerResizeRuntime.swift:87` (followFocus=false), `RailController.swift:883` -> `readerSnapshot`.
- Commandes : `sharedSnapshot` (règle 150 ms inchangée) et `invalidateSharedSnapshot` (9 appels).
- Écritures de cadres : `setFrame` / `applyTreeScope` -> `republishSharedSnapshot` (DaemonSnapshot.swift:2223).
- Rail : minuterie 1 s (`RailController.start`), watchers fichiers (`RailFileWatchers.swift`), ScreenCaptureKit.
- Aucun point d'entrée réseau ou entrée utilisateur non fiable dans le diff. Les fichiers lus
  (`recording.json`, `stages.json`, `rail.json`) appartiennent à l'utilisateur local.

## Invariants vérifiés à la lecture

1. A-01 : la génération est lue au départ du relevé (producteur : `snapshot()` l. 351 ;
   lecteur : `ReaderAcquisition.observation` l. 253), jamais à la publication. Un événement pendant
   le relevé rend la publication non réutilisable au-delà de 150 ms. Les accès sont sous `lock`.
2. A-01 : la réutilisation silencieuse exige génération égale, âge < plafond (= filet), même
   empreinte du fichier d'état, même config ; activée seulement si `enableLiveEvents` (main.swift:425).
3. A-01 : les échos de nos écritures sont absorbés par l'observateur (A1) ; les cadres écrits sont
   republiés (`republish(frames:)` conserve la génération) ; un échec d'écriture invalide le cache.
4. C-01 : énumération SCK seulement si un identifiant demandé manque et n'est pas en attente
   d'absence (5 s) ; un échec de capture retire la fenêtre du cache ; `prune` borne le cache aux membres représentés.
5. C-02 : statut relu si le watcher le signale (écriture atomique -> événement du dossier, vérifié dans
   `TargetMacroService.swift:125`) ou si le PID n'est plus vivant.
6. C-03 : la carte dessine ses vignettes dans `draw(_:)` depuis `thumbnails` (StageCardView.swift:551) ;
   `needsDisplay = true` suffit. Les écrans masqués ne sont pas rafraîchis ; leur réaffichage change
   la signature de structure (`hidden=`) et provoque un rendu complet.

## Fichiers lus (extension aux appelants)

DaemonSnapshot.swift (200-440, 2215-2245, 2410-2600), TickScheduler.swift (1-200), main.swift (300-470, 576),
RailController.swift (60-160, 860-1085), RailPanel.swift (300-340), RailThumbnailStore.swift (1-200),
StageCardView.swift (80-150, 215, 540-560, 780-800), RailFileWatchers.swift (1-75),
TargetMacroService.swift (105-140), RailSettings.swift (129-140), StageStore.swift (160-186),
JSONPersistence.swift (30-42), RailRuntimeState.swift (35-45), tests Spec048*, spec/plan/tasks/research/
reuse-audit/validation, ADR 009/013/015, mesures (script et JSON).

## Zones non lues et inconnues

- `AXWindowEventObserver` : ensemble exact des notifications abonnées par application (titre, réduction).
  Limite déjà documentée par l'ADR 015 (délai jusqu'au filet, 2 s).
- Comportement ScreenCaptureKit avec un `SCWindow` mémorisé longtemps : non vérifié à l'exécution
  (aucun accès au bureau ; pas de redémarrage du daemon autorisé).
- Rendu visuel réel (bordure, vignettes, indicateur) : non vérifié, couvert par tests seulement.
- Mesures avant/après : relues, non refaites (pas de redémarrage autorisé).
