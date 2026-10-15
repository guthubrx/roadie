# Plan

Ajouter à SystemSnapshotProviding un inventaire CG seul des identifiants et PID, incluant les Spaces inactifs. Repli nil pour les fournisseurs sans cette capacité. SnapshotService ne retient que les identités de membres persistants, non fermés et non contredits par le relevé courant. Utiliser cette preuve pour la conservation des membres et la projection du rail, sans ajouter ces fenêtres au snapshot de placement.

Livraison : patch isolé sur main, puis application à une copie vérifiée des 264 sources/tests de la version installée combinée. Garder les travaux parallèles et les corrections 035 séparés.

Preuves : captures natives avant/après, inventaires réels et contrôle des groupes ; diaporama autonome dans preuves-corrections/2026-10-15-036-stages-plein-ecran/preuves.html. Captures et manifestes bruts hors Git.
