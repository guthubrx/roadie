# Constats - session 051 readonly (révision 0)

Auditeur : Claude (Opus), `independent=false`. Preuves : lecture de source, tests du run
20261018T180405368306Z. Aucune reproduction runtime (pas d'accès au bureau, aucun redémarrage).

## F1 - MEDIUM - R5 contredite en mode `run` : la session de geste relève encore à chaque clic gauche

- Fichier : `Sources/roadied/main.swift:429` (cible de `UserInputActivity.observeGestures`).
- Cause : chaque `leftMouseDown` vu par le moniteur global de `UserInputActivity`
  (`FocusFollowsMouseController.swift:140, 165-167, 188-189`) appelle la cible de geste, qui appelle
  `service.sharedSnapshot()`. Cette lecture applique la règle des 150 ms sans réutilisation
  silencieuse (`DaemonSnapshot.swift:221-228`) : au repos, la dernière publication a souvent plus de
  150 ms, donc un relevé AX complet a lieu sur le fil principal, avant tout test de barre de titre.
  La cible ajoute aussi une ligne `window_gesture_target` à `events.jsonl` à chaque clic (l. 432).
- Interaction avec la correction C-05 : avant la 051, le rail (`makeContext` -> `sharedSnapshot`)
  et la session de geste partageaient la même publication de 150 ms (état de relevé partagé par
  chemin d'état, `DaemonSnapshot.swift:159`). Le pré-filtre du rail retire donc un appel, mais pas
  le relevé par clic, dans le mode par défaut (`roadied run`, événements en direct, `main.swift:479-489`).
  Le gain de C-05 existe seulement sans session de geste (`--no-live-events`, composant rail seul).
- Exigence : R5 « Un clic hors d'une barre de titre gérée ne déclenche pas de relevé » : contredite
  dans le mode par défaut. `validation.md` ne le signale pas.
- Sévérité MEDIUM : pas de régression par rapport à la base ; coût par clic non mesuré, borné par la
  fréquence des clics humains. Une mesure de latence au clic pourrait justifier HIGH.
- Correction : décision de conception (réutiliser `readerSnapshot` et sa génération d'observation
  pour la cible de geste, ou pré-filtrer sur les cadres gérés connus), puis mesure ; à défaut,
  corriger le texte de R5 et `validation.md`.

## F2 - LOW - Variante : le menu de barre de titre relève à chaque clic droit quand il est activé

- Fichier : `Sources/RoadieDaemon/TitlebarContextMenuController.swift:212`.
- `handleRightMouseDown` appelle `snapshotService.snapshot()`, qui relève toujours
  (`DaemonSnapshot.swift:308-310`, `provider.windows()` l. 359), avant le test de barre de titre.
  Option expérimentale désactivée par défaut (garde l. 209). Antérieur à la 051, hors diff.
- Correction : tester d'abord la bande de titre sur un relevé partagé, puis relever seulement si le
  point est éligible.

## F3 - LOW - Critère de réussite non rempli : aucune mesure avant/après publiée

- Fichier : `specs/051-constats-high/tasks.md:9` (T007 non cochée).
- La spec (l. 38-40) exige une mesure au repos avec `mesure-repos.py` et des résultats publiés.
  Le commit ne contient aucun fichier `mesures/` ; `validation.md` annonce une mesure « après
  intégration ». Constitution XXII : sans gain mesuré, les optimisations restent des hypothèses.
- Correction : mesurer au repos dans les conditions de la 048 et publier avant/après, ou retirer
  ce critère de la spec.

## Points relus sans défaut
- B-01 : fenêtre de course entre la lecture sans verrou et l'empreinte publiée : un écrivain d'un
  autre processus pourrait rendre la publication décalée d'un relevé. Les écritures de `stages.json`
  passent par le daemon sur le fil principal ; risque résiduel non retenu.
- A-02 : processus sans observateur AX (mode modulaire) : un élément AX devenu invalide pour un même
  CGWindowID garderait l'état `lastKnown`. Limite déjà écrite dans `validation.md` ; pas de scénario
  observé. Non retenu comme défaut.
- A-05 : pas de `stop()` sur le contrôleur, donc pas de minuterie relancée après arrêt.
- D-03 : `layoutPlan` lit l'arbre muté dans `stageStore.state()` : la commande applique bien le nouvel arbre.
