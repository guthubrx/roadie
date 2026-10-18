# Session 035 — Audit global Roadie

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

Statut : corrections terminées ; un défaut de coût reste ouvert. Contrôle V15 final conservé dans le dossier audits. Demande explicite : audit de tout Roadie avec corrections, trois passes si nécessaire.

- R035-01 : examiner les sources réellement installées, leurs dépendances, scripts et contrats, sans écraser les travaux parallèles.
- R035-02 : conserver une preuve avant correction et vérifier les variantes et comportements valides.
- R035-03 : limiter les corrections à trois passes, puis contrôler sans modifier les sources.
- R035-04 : calculer et valider les notes V15 ; exposer les limites et les défauts restant actifs.
- R035-05 : ne pas committer ni installer automatiquement pendant cet audit.

Les sources combinées ont été copiées et leurs 264 empreintes de livraison 034 vérifiées. La branche main et l'application en cours restent intactes.
