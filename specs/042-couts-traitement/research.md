# Recherche locale et décisions

Source : revue statique du 18 octobre, f96216c0. Les fichiers JSON et TOML ont déjà des caches. Les captures ont déjà un budget et un seul lot en vol. Ne pas ajouter de cache global non borné, de dépendance ou de rééquilibrage BSP.

Les lecteurs partagent SnapshotProcessState. SystemSnapshotProviding est Sendable ; les écrans AppKit nécessitent une collecte sûre sur le fil principal. Le producteur du tiler reste piloté par TickScheduler : les nouveaux lecteurs ne doivent pas modifier ce contrat ni appliquer un état ancien après invalidation.

Les parcours de secours AX doivent conserver l’unicité et la quarantaine. Une fenêtre écrite invalide son cadre mémorisé. La recherche conserve l’ordre des rangs et les labels attribués. Le rail conserve les originaux pour les hit-tests ; les copies restent non interactives.
