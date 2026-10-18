# Recherche locale et décisions

Source : revue statique du 18 octobre, f96216c0. Les fichiers JSON et TOML ont déjà des caches. Les captures ont déjà un budget et un seul lot en vol. Ne pas ajouter de cache global non borné, de dépendance ou de rééquilibrage BSP.

Les lecteurs partagent SnapshotProcessState. SystemSnapshotProviding est Sendable ; les écrans AppKit nécessitent une collecte sûre sur le fil principal. Le producteur du tiler reste piloté par TickScheduler : les nouveaux lecteurs ne doivent pas modifier ce contrat ni appliquer un état ancien après invalidation.

Les parcours de secours AX doivent conserver l’unicité et la quarantaine. Une fenêtre écrite invalide son cadre mémorisé. La recherche conserve l’ordre des rangs et les labels attribués. Le rail conserve les originaux pour les hit-tests ; les copies restent non interactives.

## Revue indépendante, premier passage
- Concurrence des caches AX : risque confirmé. Ajouter des générations aux publications et purges ; une invalidation d’événement ou un scan plus récent rend les anciennes écritures inopérantes. Conserver le cache utile aux processus lecteurs autonomes.
- Horodatage : retenir la fin effective de l’acquisition, avant la reprise de MainActor. Le début du scan n’est pas retenu : il rendrait immédiatement périmés tous les relevés prenant plus de 150 ms et provoquerait des rescans continus (régression déjà couverte par slowSnapshotIsReusableAfterPublication).
- Attente : conserver une seule acquisition ; ne pas en lancer une seconde après un délai arbitraire. Les appels AX ont déjà un délai et une quarantaine. L’attente asynchrone ne bloque pas MainActor.
- AppKit : NSRunningApplication est documenté comme thread-safe par Apple ; NSWorkspace est consulté sur MainActor avant la lecture AX du focus. Source primaire : https://developer.apple.com/documentation/appkit/nsrunningapplication . Les écrans restent sur MainActor.
- Limite de revue : le lecteur externe n’avait pas de shell ; il a lu les fichiers, sans comparer les commits. Le diff sera fourni au passage final.
