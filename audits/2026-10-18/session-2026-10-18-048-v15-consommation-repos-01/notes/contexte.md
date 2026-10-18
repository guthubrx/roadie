# Preuve de contexte - audit V15 readonly, session 048 (consommation au repos)

Racine figée : `/private/tmp/roadie-audit-048` (worktree détaché, commit ab9b28e958fb246525e5e80c77dafa11c70288b5).
Revue différentielle : base d32105c863953a77d0f76ec50b4a571b3f80d3d2. Mode readonly, un cycle.
Auditeur : Claude (Opus), même agent que l'orchestration, `independent=false`. Aucune revue indépendante.

## Reprise d'une session antérieure

La session fix `session-2026-10-18-048-consommation-repos-01` (versée dans ce commit, dossier
`audits/`) a audité les mêmes sources avant commit. Comparaison des empreintes : les 25 fichiers
sources/tests/docs de sa révision 1 sont identiques au commit, sauf `.gitignore`,
`research.md`, `validation.md` (texte) et trois échantillons `sample` désormais ignorés.
Ses conclusions ne sont pas des preuves ici : chaque point a été relu sur le commit figé.

## Biens à protéger

- Exactitude de l'état affiché (bordure, rail, poignées, focus-souris) face aux fenêtres réelles.
- Coût CPU au repos du daemon `roadied` (objet de la spec).
- Indicateur d'enregistrement de cibles.
- Contrats ADR 009/013 amendés par l'ADR 015.

## Acteurs et points d'entrée

- Tiler (`Sources/roadied/main.swift`, `startTilerComponent`) : événements AX, NSWorkspace,
  écrans, réveil, réglages, filet périodique. Tous passent par `TickScheduler.request`, qui
  appelle `onObservationChange` hors filet (`TickScheduler.swift:92`).
- Lecteurs : bordure, focus-souris, poignées (`DividerResizeRuntime`), rail -> `readerSnapshot`.
- Réutilisation silencieuse activée seulement avec les événements en direct (`main.swift:425`).
- Rail : minuterie 1 s, watchers de fichiers, ScreenCaptureKit (`RailThumbnailStore`).
- Aucun point d'entrée réseau ni entrée non fiable ajoutés. Fichiers lus : `~/.roadies/*.json`
  de l'utilisateur local. Script de mesure : `ioreg`, `pgrep`, `ps`, `sample` en liste d'arguments.

## Invariants vérifiés à la lecture

1. Génération lue au départ du relevé (`DaemonSnapshot.swift:351` producteur, `:253` lecteur),
   jamais à la publication ; accès sous `NSLock`.
2. Réutilisation silencieuse : génération égale, âge < `quietReuseCap` (= filet), même empreinte
   de `stages.json`, même config (`DaemonSnapshot.swift:2515`).
3. Republication des cadres écrits : la génération est conservée (`:2587`).
4. C-01 : énumération SCK seulement si un identifiant demandé manque hors attente d'absence (5 s) ;
   une capture nil retire l'entrée ; `prune` borne le cache aux membres représentés.
5. C-02 : statut relu après signal du watcher, disparition du PID, arrêt du rail (`stop()`
   remet `recordingStatusDirty` à vrai, `RailController.swift:136-138`) ou réaffichage de l'indicateur.
6. C-03 : signature des vignettes séparée de la signature de structure ; `updateThumbnails`
   redessine seulement si une image change ; un écran masqué n'est pas rafraîchi.
7. Lectures de fichiers d'état : `JSONPersistence.read` garde la valeur décodée par chemin et
   la revalide par `fstat` (mtime, taille, inode) ; fichier inchangé ni relu ni décodé
   (`JSONPersistence.swift:211-235`, test `StatePersistenceTests.swift:66`).

## Fichiers lus (extension aux appelants)

Diff complet des 7 sources et 2 tests ; `JSONPersistence.swift` (1-80, 180-340) ;
`StageStore.swift:170-186` ; `RailRuntimeState.swift:35-45` ; `DividerResizeRuntime.swift:30-40, 80-90, 160-170, 265-275` ;
`StatePersistenceTests.swift:60-90, 540-555` ; spec, plan, tasks, research, validation ; ADR 015.

## Zones non lues et inconnues

- `AXWindowEventObserver` : notifications abonnées par application (limite déjà écrite dans l'ADR 015).
- Comportement ScreenCaptureKit avec un `SCWindow` mémorisé : non observé (pas d'accès au bureau).
- Rendu visuel réel et mesures CPU : non rejoués (aucun redémarrage ni installation autorisés).
