# Plan de correction

Reprendre la base 036 combinée déjà installée. Figer les reproductions avant correction
dans un audit V15 fix ; trois passes au maximum, suivies d'une revue finale en lecture seule.

1. Rejouer la perte d'inventaire via ReplayableSnapshotProvider et la disponibilité AX
   sur le même écran. Réutiliser les doubles de frontière des tests 034/036.
2. Importer uniquement le patch de corrections 035, avec ses tests. Préserver les autres
   changements installés et ne toucher à aucun autre worktree.
3. Réparer l'assemblage du fournisseur et la reprise. Mettre à jour les observations des
   membres en une passe, sans nouvel état durable ni nouveau moteur.
4. Observer un panneau de sélection fictif sur le Mac. Reproduire les échanges du fichier
   de glisser dans des fichiers isolés. Corriger seulement les mécanismes établis.
5. Tests ciblés, témoins avant/après et mesures aux mêmes tailles ; suite complète séquentielle.
6. Release signée, sauvegarde runtime, installation et unique redémarrage final vérifié.
7. Refaire les circuits natifs avec des fenêtres témoins, conserver les captures originales
   hors Git et livrer un diaporama autonome des effets visibles.

Minimalisme : protocole/fournisseur et garde existants ; mise à jour locale par lot ;
aucune dépendance ni nouveau service. Pas de purge de l'état utilisateur.
