# Consolidation du 18 octobre 2026

Les sept mécanismes corrigés et leurs tests sont déjà intégrés à `main` par
`06245802`. Les fichiers propres à l'audit sont identiques à la version actuelle.
Les autres écarts sont des versions antérieures aux corrections des sessions 036–039.

Le coût quadratique signalé dans le compte rendu historique a ensuite été traité
par `PersistentStageState.updateWindowObservations`, également livré dans `06245802`.
Cette mise à jour par lot conserve les observations des membres, épinglages et signets.
La présence du défaut dans le rapport initial ne décrit donc pas le code courant.

Les documents d'origine sont conservés ici avec une mention historique. Les rapports
bruts, journaux et copies des moteurs d'audit restent dans la sauvegarde locale :
/Users/moi/Archives/roadie-consolidation-20261018/035-audit-global/files.tar.gz.

Aucune modification du programme ni nouvelle mesure de performance pendant cette consolidation.
