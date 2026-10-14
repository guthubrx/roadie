# Plan — session 029

Swift, AppKit, Accessibility et Swift Testing. Réutiliser
`SnapshotProcessState`, `PersistentStageState`, `StageStore`,
`RailFileWatcher` et `RailDisplayContent`.

## Pourquoi

Roadie distingue déjà une destruction confirmée d'une absence transitoire.
Cette preuve nettoie l'arbre BSP, mais pas encore l'appartenance persistante.
Le plan propage la même preuve jusqu'au `StageStore`. Le watcher existant peut
alors actualiser le navrail sans nouvelle boucle de lecture.

## Flux retenu

1. Une fermeture AX enregistre l'identifiant détruit et demande une passe.
2. Tant que CoreGraphics retourne cet identifiant, Roadie bloque sa
   réinsertion et programme une reprise après 50 ms, au plus dix fois.
3. Au premier snapshot où l'identifiant sort de `stageManagedWindowIDs`, le
   writer marque le membre `confirmedClosedAt` sans supprimer son appartenance.
4. L'écriture du `StageStore` déclenche son watcher. Le navrail reconstruit son
   contenu après le regroupement existant de 20 ms.
5. Si la dernière fenêtre a disparu, le filtre existant retire la stage dans
   cette même reconstruction.

La preuve utilisable pour marquer la fermeture expire après cinq secondes.
Le tombstone historique de l'arbre garde son comportement actuel. La présence
dans `stageManagedWindowIDs` gagne toujours contre la preuve de fermeture.

Les reprises sont comptées par identifiant. Seul un snapshot écrivain les
incrémente. Une notification répétée ne remet ni la date ni le compteur à zéro.

## Fichiers prévus

- `Sources/RoadieDaemon/DaemonSnapshot.swift` : preuve horodatée, marquage des
  membres fermés et état des reprises courtes.
- `Sources/RoadieDaemon/LayoutMaintainer.swift` : exposer l'échéance courte et
  bornée des fermetures encore visibles dans CoreGraphics.
- `Sources/RoadieDaemon/StageStore.swift` : champ optionnel persistant et
  remise à zéro quand la fenêtre est revue ou remappée.
- `Sources/RoadieDaemon/RailController.swift` : signature du watcher et filtre
  visuel du nouveau marqueur.
- `Tests/RoadieDaemonTests/SnapshotServiceTests.swift` : appartenance, stage
  vide, doublon, ancien événement et absence transitoire.
- `Tests/RoadieDaemonTests/TickSchedulerTests.swift` ou tests du maintainer :
  reprise bornée lorsque CoreGraphics conserve brièvement l'identifiant.
- `Tests/RoadieDaemonTests/WindowPresentationStateResolverTests.swift` :
  conservation de la grâce visuelle des absences transitoires.

## Compatibilité et complexité

Le `StageStore` reste le contrat entre les modes monolithique et modulaire.
Le format persistant gagne un champ optionnel, compatible avec les fichiers
existants. Le traitement reste linéaire selon les stages
et leurs membres. Aucun appel AX par vignette et aucune dépendance ne sont
ajoutés.

Les pins, signets et surcharges de placement gardent leurs grâces existantes.
Ils ne participent pas au contenu visible du navrail. Un échec rare d'écriture
du `StageStore` reste traité par le filet de sécurité existant. Son API ne
retourne pas de preuve d'écriture et sa refonte est hors périmètre.

Le membre persistant reste disponible après une terminaison d'application. Le
rattachement SPEC-016 peut donc restaurer la fenêtre dans sa stage. Le marquage
est effacé quand la fenêtre est revue ou remappée.

## Vérification

- mesurer avant le code le chemin complet disponible dans les journaux ;
- mesurer après correction les modes monolithique et modulaire avec la même
  séquence, ou documenter séparément le mode non activable sans perturber le
  runtime courant ;
- exécuter les tests RoadieDaemon ciblés ;
- exécuter la suite Swift complète ;
- construire le binaire de livraison ;
- installer selon le script Roadie existant ;
- vérifier le runtime et refaire une fermeture réelle ;
- pousser la branche intégrée, puis nettoyer seulement le worktree 029.

## Gates de constitution

- Diagnostic avant modification : satisfait par le code et les journaux réels.
- Réutilisation : satisfaite, aucun nouveau service ni registre.
- Tests avant livraison : requis par les tâches T008 à T011.
- Preuve de runtime : requise avant clôture.
- Git : branche isolée, message sans trace d'outil, push vérifié.
