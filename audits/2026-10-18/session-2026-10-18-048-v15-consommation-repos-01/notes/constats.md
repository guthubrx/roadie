# Constats - session 048 readonly (révision 0)

Auditeur : Claude (Opus), `independent=false`. Aucune revue indépendante.

## Corrections de la session fix antérieure, vérifiées sur le commit

- F1 (LOW, statut d'enregistrement conservé après `stop()`) : `RailController.swift:136-138`
  remet `recordingStatusCache` à nil et `recordingStatusDirty` à vrai. Présent. Pas de test dédié
  (le redémarrage du rail crée des panneaux réels) ; suite complète verte.
- F3 (LOW, plan à 1 s) : `plan.md:5-12` décrit `allowQuietReuse` et le plafond égal au filet ;
  `research.md:35-37` garde la valeur initiale avec la mention « Révisé après la revue du plan ».
  Présent. Ces deux points ne sont plus des défauts du code audité ; ils ne sont pas recomptés.

## F2 - réfuté - « la minuterie du rail relit et décode stages.json et rail.json chaque seconde »

- Identité conservée : `spec048.r3-file-reread`, `RailController.renderPanels`,
  `unchanged-state-files-reread-per-tick`.
- Hypothèse de la session antérieure : `store.state()` (`RailController.swift:932`) et
  `railRuntimeStateStore.load()` (`:936`) lisent et décodent le disque à chaque tick, sans cache.
- Réfutation : les deux appels passent par `JSONPersistence.load` (`StageStore.swift:177`,
  `RailRuntimeState.swift:42`) -> `loadResult` -> `read` (`JSONPersistence.swift:215`). `read`
  consulte un cache par chemin, puis `readSigned` ouvre le fichier et compare la signature `fstat`
  (mtime s/ns, taille, inode, `:323-334`) ; si elle est égale, il rend la valeur en cache
  (`:223-225`) sans lire les octets ni décoder. Le test `StatePersistenceTests.swift:66-85`
  compte les décodages et vérifie qu'un fichier inchangé n'est pas redécodé ; il passe dans le
  run 20261018T175828587883Z.
- Coût restant par tick : `open` + `fstat` + `close`, O(1), pour deux fichiers. Ce n'est pas une
  « relecture de fichier inchangé » au sens de R3. La session antérieure s'était arrêtée à
  `JSONPersistence.swift:30-42` sans suivre `read`.
- Verdict : réfuté (preuve source et test). Confiance haute.

## F4 - réfuté - variante « les poignées décodent stages.json toutes les 150 ms »

- Identité conservée : `spec048.r3-file-reread`, `DividerResizeCoordinator.update`,
  `stage-state-reread-every-150ms`.
- `DividerResizeRuntime.swift:167` appelle `service.effectiveStageStore.state()` ->
  `StageStore.state()` -> même `JSONPersistence.read`. Même réfutation : `fstat` par tick, sans
  décodage si inchangé. Fichier hors diff ; verdict conforme à `validation.md:71-75`.

## Aucun nouveau défaut confirmé

Points relus sans défaut : rafraîchissement des vignettes avant la garde `changedDisplays`
(`RailController.swift:1018-1023`), cadres vivants pour la taille de capture, retrait d'un
`SCWindow` après capture nil, génération incrémentée par `&+=`, plafond `max(0, cap)`.
Limite : le comportement de ScreenCaptureKit avec un `SCWindow` ancien n'est pas observé à l'exécution.
