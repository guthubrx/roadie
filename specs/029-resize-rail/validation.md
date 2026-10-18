# Validation de la session 029

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

## Reproduction sur les anciennes logiques

Le 15 octobre 2026, les quatre suites ciblées compilent puis échouent :
44 tests, 91 constats, sans arrêt brutal du processus.

| Suite | Constats |
|---|---:|
| Spec029ResizeTests | 14 |
| Spec029RailTests | 26 |
| Spec029DisplayParkingTests | 32 |
| Spec029RestorationRetryTests | 19 |

Journal local : /private/tmp/roadie-029-red-tests.log.
Les sources corrigées sont restaurées après la comparaison.

## Vérification après intégration

Premier passage : 43 tests sur 44 réussissent. Rail, retour d’écran et refus bornés passent. Le cas du geste après une garde de plein écran reste à corriger avant livraison.

Le diagnostic de cette fixture montre une source encore cachée à x999 avant le clic. Les tests de garde rétablissent une vraie fenêtre visible. Un cas distinct de déplacement retenu par une commande réarme désormais une échéance future, avec le même plafond absolu.

La revue a permis de reproduire une réponse partielle publiée après la relecture : 18 tentatives en mode libre, au lieu de deux au plus. Journal : /private/tmp/roadie-029-delayed-red-tests.log. Le budget conserve maintenant la continuité d’un mouvement vers la cible refusée. Un geste confirmé traité libère le refus de sa fenêtre.

Premier passage complet : 1 505 tests dans 160 suites, un échec dans une ancienne fixture d’affectation par position. Les 47 nouveaux tests passent. Cet échec venait de la configuration personnelle lue par une fixture ; celle-ci reçoit maintenant une configuration explicite sans workspaces. Les traces temporaires ont été retirées. Journal : /private/tmp/roadie-029-full-tests.log.

Les 26 tests des scripts passent en 23,555 s. Journal : /private/tmp/roadie-029-script-tests.log.

## Derniers compléments avant le premier essai

Les tests de revue du parking reproduisent trois cas défectueux, avec six constats : /private/tmp/roadie-029-parking-review-red-tests.log. Une copie `.restored` revient seulement avec son placeholder `.parked` dans le bureau/écran d’origine, reconnu par identité physique ou logique. Une ancienne copie sans ce témoin reste où elle est. Le déplacement explicite vers un écran détache le stage. Aucun nouveau champ persistant.

Les refus directs gardent leur budget pendant une progression monotone différée vers la cible. Un geste confirmé puis traité le libère. Un clic simple ne renouvelle ni génération ni budget. Pour toutes les commandes, seules les écritures abouties arment la stabilité.

**Suite avant le premier essai : 1 514 tests Swift dans 162 suites, tous verts en 8,422 s.** Journal : /private/tmp/roadie-029-final-tests.log. Les 26 tests des scripts restent verts en 23,555 s.

Le rendu AppKit hors écran produit 12 images : quatre modes du rail, aux polices 8, 16 et 48, avec une largeur de 90. Dossier : /private/tmp/roadie-029-rail-renders. L’inspection de trois cas — piles à 48, icônes à 48 et mosaïque à 8 — montre un numéro lisible sans recouvrir les aperçus. Cette inspection ne remplace pas l’essai utilisateur.

Les relectures indépendantes ont aussi identifié une carte vide créée à tort après un changement d’identifiant automatique. Quatre tests ciblés reproduisent cinq constats dans /private/tmp/roadie-029-stage-identity-red-tests.log. La correction conserve la nature automatique du nom et les noms personnels. Un stage vide nommé, de mode différent ou avec un arbre explicite n’est plus écrasé par un déplacement entre écrans.

La dernière suite complète confirme le résultat de 1 514 tests dans 162 suites, tous verts en 8,422 s, après cette correction. Aucun commit de code ni publication à ce stade.

## Synthèse des revues

Les constats fonctionnels des quatre tours menés par deux relecteurs sont traités. La revue couvre les gestes différés, les budgets de refus, l’ordre du rail, le retour d’écran, les identités des stages déplacés, la complexité et le minimalisme.

Les objections non bloquantes sont documentées : l’échéance minimale testée au-delà d’une seconde exclut une relance toutes les 50 ms ; un clic simple ne renouvelle volontairement pas la génération ; seules les écritures abouties de toutes les commandes arment la stabilité. Les interfaces publiques de délégation sont conservées pour compatibilité. Un ancien placeholder dont le mode d’origine est inconnu est conservé par prudence.

## Première installation et santé réelle — avant essai non concluant

Installation signée réussie dans /Users/moi/Applications/Roadie.app et /Users/moi/.local/bin/roadie, puis redémarrage par `make restart`. Version conservée : 0.5.0. Daemon PID 53846 et surveillance de restauration PID 53859. Les quatre contrôles sont verts, avec Accessibilité et configuration valides : /private/tmp/roadie-029-installed-health.json.

Signature vérifiée, certificat `roadied-cert` conservé avec l’empreinte 78a75e8032f190a20072eb91cc2919aac344ef78. Le SHA-256 de /Users/moi/.config/roadies/roadies.toml reste c3b1cc4bd5f3cd8ae144758d63565645d269458364396ec2e3d51f8e4eb17d9c.

Sur les 52,5 premières secondes observées autour du redémarrage, aucun `layout_failed` ni rafale de restaurations du mainteneur. Trois refus `restore.unhide_all_failed` concernent la restauration d’arrêt ; ils ne prouvent pas une boucle du nouveau daemon. Observation courte uniquement : /private/tmp/roadie-029-post-restart-events.json.

Journaux : /private/tmp/roadie-029-install.log et /private/tmp/roadie-029-restart.log. L’essai utilisateur qui suit reste non concluant pour le redimensionnement ; cette installation ne constitue donc pas la livraison finale. Aucun commit de code ni publication avant cette validation.

## Reprise après l’essai utilisateur non concluant

L’utilisateur signale encore un retour de taille. Les événements du 15 octobre à 05:41:38 CEST montrent la fenêtre 75411 passer de 1 055 à 1 382 points par `layout_external_change_reverted`. Le tick AX précède le callback de relâchement. Le harnais attendait la fermeture de la session, alors que le runtime ne regardait que les boutons physiques. Cette différence masquait la course.

La garde commune `blocksLayout` protège maintenant le scheduler et le mainteneur jusqu’à `mouseUp`. Preuve rouge : /private/tmp/roadie-029-release-race-red-tests.log, un test et six constats. Le même test passe après correction : /private/tmp/roadie-029-release-race-green-tests.log.

Des clics sur le bord d’iTerm sont aussi classés sans cible, à 0,836 et 4,188 points du cadre. L’ordre CG réel contient des bordures décoratives derrière leur parent. Le picker autorise désormais une poignée devant le premier intérieur inéligible ; un obstacle placé devant reste bloquant. Les anciens points de test touchaient le maxY exclu de leur obstacle. La nouvelle preuve rouge couvre son intérieur et les coordonnées réelles : /private/tmp/roadie-029-picker-red-tests.log, huit tests et quatre constats.

Les événements `window_gesture_target` indiquent maintenant le premier intérieur rencontré, son application, son scope et son statut de candidat. Aucun titre n’est ajouté. La suite complète après reprise passe : **1 520 tests Swift dans 163 suites, tous verts en 8,889 s**. Journal : /private/tmp/roadie-029-resize-followup-full-tests.log. Les scripts sont inchangés ; leurs 26 tests étaient verts en 23,555 s lors du contrôle précédent.

La revue ciblée 5 est terminée sans blocage prouvé. Le journal /private/tmp/roadie-029-resize-followup-install.log concerne l’installation lancée avant le dernier garde-fou ; l’installation finale du garde-fou est lancée séparément et sa réussite est consignée ci-dessous. Un nouvel essai utilisateur reste requis. Le PID 53846 décrit uniquement la première installation. Aucun commit de code ni publication.

## Garde-fou après la revue 5 — tests validés, essai réel attendu

Le retour de revue ne démontre aucun blocage de la correction. Un repli court couvre toutefois la perte éventuelle de `mouseUp`. `blocksLayout` attend normalement le callback. Après un seuil de 300 ms depuis le premier relâchement physique observé, il clôture le geste une seule fois et laisse la passe le consommer. Un bouton réellement maintenu n’expire pas ; un `mouseUp` tardif ne rejoue pas le geste.

Ce repli est consulté par les événements ou le filet périodique existant. Il ne promet pas une clôture à exactement 300 ms de temps réel. Les résultats de 1 520 tests ci-dessus précèdent ce dernier ajout. La baseline sans récupération produit 16 constats dans 20 tests d’une suite : /private/tmp/roadie-029-release-recovery-red-tests.log. La suite complète avec correction passe : **1 526 tests dans 163 suites, tous verts en 7,170 s**, dans /private/tmp/roadie-029-release-recovery-full-tests.log.

Avant le dernier redémarrage, une observation identifiait le daemon PID 37751, démarré à 05:51:43 CEST, et son watcher PID 37783. Le PID 53846 appartient uniquement à la toute première livraison. Ces observations restent historiques.

## Installation finale après reprise

L’installation finale est terminée et signée avec `roadied-cert`, empreinte 78a75e8032f190a20072eb91cc2919aac344ef78. Journal : /private/tmp/roadie-029-release-recovery-install.log. Le redémarrage `make restart` est terminé ; le nouveau daemon a le PID 60128 et son watcher le PID 60634. Journal : /private/tmp/roadie-029-release-recovery-restart.log.

Le socket a mis quelques secondes à apparaître au démarrage. La vérification finale est verte : quatre contrôles de santé réussis, Accessibilité et configuration valides. Preuve : /private/tmp/roadie-029-release-recovery-health.json. Le SHA-256 de /Users/moi/.config/roadies/roadies.toml reste c3b1cc4bd5f3cd8ae144758d63565645d269458364396ec2e3d51f8e4eb17d9c.

L’observation de 04:00:50Z à 04:01:59Z inclut l’arrêt de l’ancien daemon. Aucun `layout_failed` ni `external_change_reverted` n’apparaît pendant cette fenêtre. Trois `restore.unhide_all_failed` appartiennent à la séquence d’arrêt ; ils ne démontrent pas une boucle du nouveau daemon. Preuve : /private/tmp/roadie-029-release-recovery-event-counts.json. Ces quelque 70 secondes ne valident pas le glissement natif. La santé finale relue reste à quatre contrôles réussis sur quatre.

T055 est terminée : tests, revue ciblée, installation, redémarrage et santé vérifiés. T053 reste ouverte pour le nouvel essai utilisateur ; T054 reste ouverte pour la clôture Git. La résolution du défaut natif n’est pas encore confirmée. Aucun nouveau commit ni publication.

## Observation runtime du 2026-10-15 (08:15 CEST) — T053 non validée

Version installée à 07:40:44 (PID 2722). Deux gestes de redimensionnement utilisateur sont journalisés après l'installation :
- 07:48:08 : `layout_manual_gesture` fenêtre 37486, bord gauche, cadre 1267,38 775x540. Dans la même seconde : `layout_external_change_reverted` fenêtre 37486, observé 1267,38 775x540, cible 567,38 1475x540, puis `layout_apply` cause `ax:AXWindowResized`. **La taille choisie est annulée.**
- 07:48:26 : `layout_manual_gesture` fenêtre 84628, bord gauche. Aucune annulation journalisée ; le voisinage est réécrit (`layout_apply` 75411, 84625).

Contexte du premier cas : changement d'espace à 07:48:00 (`space_did_change`, `windows.missing_reconciled`, `space_transition_guard` member_return), `layout_stable` à 07:48:06, geste deux secondes plus tard.
Émetteur : Sources/RoadieDaemon/LayoutMaintainer.swift:1285.

Disjoncteur (constitution, article IV) : le défaut de redimensionnement a reçu plus de trois corrections successives. Arrêt des correctifs ; nouvelle hypothèse à établir sur cette donnée avant tout patch, avec validation utilisateur.
