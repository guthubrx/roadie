# Contexte d'audit

Révision de départ : 5ed75b0532c4179c2b6b7d6a4a88e5e2ec2e92fd. Périmètre demandé : dépôt complet. L'inventaire initial du moteur contient 1 223 fichiers hors dossiers d'audit et fichiers ignorés : sources Swift, tests, scripts, configuration, documentation et spécifications.

Biens à protéger : configuration, workflows, fichiers et disposition des fenêtres de l'utilisateur. Acteurs : utilisateur local, applications locales et auteurs de workflows importés. Entrées : ligne de commande et socket local, fichiers de configuration, archives de workflows, API macOS et état des fenêtres. La socket locale est créée avec les permissions 0600. Des workflows peuvent exécuter des scripts avec les droits de Roadie : une archive doit être considérée comme du code exécutable.

Invariants : une commande ne doit pas supprimer des données voisines ; les écritures d'état doivent préserver les données en cas d'échec ; les accès aux fenêtres et aux fichiers doivent rester bornés ; les chemins d'erreur doivent être signalés. Dépendance Swift verrouillée : TOMLKit. Les règles Semgrep locales et leur couverture du langage ne remplacent pas une lecture Swift.

Lecture approfondie initiale : `CLICommandRouter`, `AlfredWorkflow`, `AlfredWorkflowIndex`, `AlfredAutomationTasks`, `CommandSocketServer`, `JSONPersistence`, `FileLock`, `ComponentLockFile`, les tests et les spécifications associés. Le reste du dépôt n'est pas encore qualifié individuellement. La suite de l'audit doit préciser les lectures et les contrôles effectivement réalisés.
