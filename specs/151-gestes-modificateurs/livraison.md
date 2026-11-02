# Livraison151 — gestes depuis le contenu

2 novembre 2026. Fonctionnalité installée et vérifiée sur le Mac :
- Ctrl + glisser gauche : déplacer.
- Ctrl + Alt + glisser gauche : redimensionner, avec adaptation des voisines tuilées.
- Réglages immédiats et désactivables dans Tuilage ; choix exact de modificateurs ; Échap restaure quand le contexte reste valable.

Source finale6525a8b9 ; UUID1D14C437-8C8B-357A-BB20-50B016B79EBF ; PID29631, santé5/5. Certificat et configuration initiale conservés. Les 534 fichiers Sources/Tests correspondent à ceux des tests et du build installé. 2480tests/375suites et28scripts verts.

Deux rondes de revue de code ont traité les constats ; dernière lecture indépendante sans défaut bloquant. Les essais natifs ont ensuite révélé le marqueur de clic repris depuis sa source CG initiale. Une source privée Roadie corrige ce défaut ; la suite finale et le tap natif indépendant confirment une seule paire rendue au client. Ce dernier correctif est vérifié par le parent, sans inventer une nouvelle approbation indépendante.

Cinq parcours vérifiés : déplacement tuilé, resize source et voisines avant le relâchement, Échap avec restauration, Ctrl+clic conservé, déplacement d'une flottante avec position persistée. Contrôle des cadres par l'application fictive et relecture de l'arbre. Le client reçoit le clic et Ctrl ; son menu contextuel n'est pas revendiqué.

Preuves : diaporama vérifié, couverture partielle des appuis physiques et de l'interface des réglages. Fichier autonome : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/preuves-corrections/2026-11-02-151-gestes-modificateurs/preuves.html. Captures réelles de fenêtres fictives, navigation8/8 et pause vérifiées. Originaux et manifestes hors Git.

Nettoyage : fenêtres et stage fictives fermées/supprimées, épinglage de test disparu, stages initiales rétablies. Build1,4Go, application de test, sonde d'événements binaire et retour arrière149 devenu redondant retirés ; total1 494 385 481octets. Branche150 intégrée supprimée localement et à distance. Worktree du fil et branche151 encore utilisés conservés. Exécutables installés, retour arrière150, symboles et preuves originales conservés hors Git. Les trois dossiers distants de revue restent gardés par Bridget après clôture de leurs tâches ; aucun retrait distant sans vérification de leurs autres usages n'est revendiqué.

Intégration main et push vérifiés à la clôture par lecture du commit distant. Aucune release numérotée ou DMG demandé ici. Détail et limites : validation.md, revue-code.md, ADR027.

## Nettoyage complémentaire demandé après livraison

Branche151 intégrée supprimée localement et à distance. Le worktree de ce fil reste conservé avec HEAD détachée sur main ; aucun worktree local obsolète ni build restant.

Cinq worktrees distants de revue retirés sur Cartae, avec leurs branches bridget :777958bd,cc3bf754,ffeba36c,73d4dc8f,fd13cdc0. Avant chaque retrait : résultat conservé, tâche arrêtée, zéro commit distinct, HEAD attendu et ancêtre du main publié, aucun changement suivi/ignoré, aucun processus utilisant le dossier par cwd/exécutable/descripteur. Retrait par git worktree remove sans force ; référence supprimée seulement avec le SHA attendu. Résultats complets archivés hors Git avant retrait. Total des cinq dossiers :215821332octets.

Les autres worktrees distants restent conservés : leur propriétaire et leur usage ne sont pas établis dans ce nettoyage. Ils ne sont pas déclarés inutiles. Les sources, tests, paramètres et exécutables actifs ne changent pas. Aucun nouveau build ni nouveau test nécessaire pour cette seule mise à jour documentaire.
