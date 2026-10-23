# Plan 058
1. Réutiliser les descripteurs, éditeurs et services de persistance. Ne modifier
   que la présentation et l'état local de dépliage.
2. Partager une ligne de formulaire : libellé/aide, contrôle et place réservée au
   rétablissement. Géométrie déterministe selon largeur et police, avec repli
   vertical uniforme à faible largeur. Mesurer les sous-vues avant placement.
3. Réutiliser cette ligne pour les réglages simples, les collections et profils.
   Réduire les titres doublés. Régler les nombres sur une ligne avec leur curseur.
4. Présenter les entrées complexes avec en-têtes identifiables et dépliage local.
5. Aide commune : largeur bornée, texte complet sélectionnable et défilement.
6. Tests géométriques et rendus natifs pour plusieurs catégories, tailles et
   polices. Revue indépendante, suite Swift, build signé, installation/restart.
7. Captures réelles et diaporama selon les accès disponibles. Docs, intégration
   main et nettoyage de la branche/build ; worktree actif conservé.
8. Retour utilisateur : compacter les lignes, raccourcir les libellés sans perdre
   les unités, onglets de même largeur dans une barre visible. Repli sur deux
   rangées à grande police. Vérifier les tailles intermédiaires et le défilement
   réel du composant d'aide natif. Annuler les anciens insets du bezel AppKit
   pour aligner les surfaces visibles des menus et des champs.
