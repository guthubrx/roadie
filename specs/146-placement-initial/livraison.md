# Livraison146 — placement initial direct

Correction demandée sur iTerm2 après apparition à une position provisoire. Désormais, le premier placement tuilé envoie directement la cible finale ; les voisines déjà placées gardent leurs animations. Découverte reprise au plus3fois50ms après création/activation sans commande ; pas de boucle au repos, mêmes gardes de geste et d’autorité.

Code ee218ff0395d5363e9ada26075c7761af1a3db4d, branche session-146-placement-initial, basea838e81e. Intégration fast-forward dans main, origin https://github.com/guthubrx/roadie.git ; push et SHA distant égaux. Le présent reçu est un commit documentaire distinct, sans autre changement de Sources/Tests.

Activation : build release signé déjà chargé, UUID758AD9DB-B909-3E17-80FC-512675038D50, PID23980, santé5/5. 520sources/tests identiques dans le checkout construit et main. Certificat stable et TOML inchangés. Aucun nouveau tag/release publique.

Vérification :40tests ciblés,2425tests/363suites et28scripts réussis. Red/green sur cible directe et reprises bornées. Essai natif iTerm2 : deux cadres de surface, naissance puis cible en133ms et stabilité7,4s ; avant,6cadres et541ms sur l’essai comparable. Tailles finales différentes : pas de benchmark ni ratio de performance généralisé. Fenêtre AppKit :4cadres en224ms environ, courts ajustements natifs taille/position conservés comme limite. La première image publiée par macOS peut rester visible ; zéro flash n’est pas promis. Deux essais instrumentés et contraintes observées conservés horsGit, aucune modification privée du système.

Revue indépendante demandée via la compétence Bridget ; admission refusée capability_unavailable, sous-cause inconnue. Aucun autre hôte/moteur n’a contourné ce refus. Relecture locale des quatre propriétaires, permissions, générations, budget, échos, complexité et tests ; aucun finding bloquant identifié dans ce périmètre. Aucun verdict indépendant ni auditV15 calculé inventé. Analyze et convergence manuels documentés dans analysis.md.
Compétence utilisée : /Users/moi/.codex/skills/bridget/SKILL.md

Preuves : diaporama vérifié,7étapes/5captures fictives,créations natives par AppleScript iTerm et AppKit. CmdN physique non rejoué. Contrôles suivant/lecture/pause/dernière étape vérifiés dans le navigateur ; aucun clic/pointeur supposé. Fichier :
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/preuves-corrections/2026-10-31-146-placement-initial/preuves.html
Bruts, traces, empreintes et rollback signé :
/Users/moi/.local/state/roadies/validation/2026-10-31-146

Nettoyage : fenêtres/processus d’essai arrêtés, stage validation146-initial supprimée par commande normale après fermeture ; stage3 externe et9 interne rétablies. Terminal initial494130 conservé. Aucun magasin global restauré ; configuration inchangée. Enregistrement temporaire LaunchServices retiré. Worktree/branche146 attachés au fil conservés ; deux analyses préexistantes préservées. Cache de compilation nettoyé après vérification de l’absence de build actif. Branche145 intégrée/poussée retirée sans force ; rollback conservé.

ETA initiale30–60min, début~17h33, activation et essais terminés vers18h02 ; clôture vers18h05, soit environ32min. Pas de réduction du périmètre. Aucun nouvel item de production en dehors des propriétaires existants ; fixture, registre et minuteur réutilisés. Limites natives explicites ; retour utilisateur sur son ouverture habituelle encore en attente à la rédaction.

Statut implémentation : Implemented. Tâches vérifiées ; première tâche non cochée : aucune. Statut livraison : livré, code chargé et fonctionnement observé ; le dernier push du reçu est vérifié avant le bilan final.
