# Axes - révision 1 (01789d19)

- Sécurité : scripts tiers lancés seulement depuis des workflows installés par l'utilisateur, groupe de
  processus propre, sortie et durée bornées ; échappements relus ; aucune écriture dans le dossier
  d'Alfred ; téléchargement des tâches sur commande explicite (curl en HTTPS vers GitHub, licence gardée).
  F2 documenté. Pas de secret.
- Logique : comportements vérifiés par 63 tests neufs (calcul, chemins, workflows, web, lot) et un
  corpus réel de 102 workflows (90 % avec une entrée complète, 77 % entiers).
- Concurrence : script hors fil principal, réponses périmées ignorées par saisie demandée, rerun
  borné à la même saisie, annulation par groupe ; lecture de dossier par génération.
- Performance : calcul O(n), chemin O(e) borné (5 000 lus, 200 gardés), mot-clé O(k), schéma 200
  étapes ; aucune mesure de latence dans la barre (critère 50 ms non mesuré).
- Tests : 2 086 tests ; barre non essayée au clavier.
- Architecture : types purs séparés (LauncherCalculator, LauncherPath, AlfredWorkflow*,
  LauncherSelection, LauncherHistory) ; effets injectés (AlfredEffects) ; `TargetOverlayPresenter` et
  `TargetModeRuntimeController` grossissent encore (vigilance).
- Observabilité : événements `launcher.workflow_filter`, `launcher.workflow.run`, `launcher.batch`,
  `launcher.url` (hôte seul), sans saisie ni sortie.
- Traçabilité : chaque session a spec, plan, research, data-model, quickstart, reuse-audit, tasks,
  validation ; écarts de convergence ajoutés et traités.
