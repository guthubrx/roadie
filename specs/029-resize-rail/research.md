# Recherche : session 029

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

La préparation repose sur le code existant, le diagnostic local /private/tmp/roadie-20261015-diagnostic.md et les conclusions ciblées des lots. Aucun contenu de courrier ni capture ne doit entrer dans les fixtures. Les décisions suivantes remplacent les propositions initiales de planification.

## Constats et décisions

| Sujet | Constat | Décision d’intégration |
|---|---|---|
| Geste sous garde | La consommation précède la sélection des scopes traitables. Un geste peut disparaître avant application. | Une seule session conservée avec identité fenêtre/PID/scope. Une nouvelle session la remplace. |
| Taille tardive | Une lecture peut encore voir le cadre de départ après relâchement. | Reprises planifiées par pas de 50 ms, fenêtre active maximale de 300 ms, plafond absolu de 2 s depuis le relâchement. |
| Clic simple | La session de souris seule ne prouve pas un glissement. | Capturer `didDrag` dans le cycle réel des événements. Aucun polling sur un clic. |
| Rail | Cartes, menus et commandes utilisent des listes différentes. | `StagePresentationOrder` centralise les positions et destinations, sans renuméroter les identifiants CLI. |
| Repère | Le fondu des noms retire l’identification lisible. | Badge de position toujours visible, indépendamment de l’opacité et du nom. |
| Écran absent | Le rang existe dans `StageOrigin.position`, mais la restauration ajoute les stages en fin. | Remplacement en place du placeholder intact ; repli sur la position si absent. Pas de tableau d’ordre supplémentaire. |
| Longue absence | La matérialisation après 60 s ne doit pas empêcher le retour ultérieur. | Après matérialisation, reprendre une copie `.restored` seulement si son placeholder `.parked` correspondant subsiste dans le bureau/écran d’origine. Sans ce témoin, respecter son emplacement actuel. |
| Refus répétés | Les placements hors arbre contournent la mémoire utile des refus. Un chemin de focus contourne aussi le budget d’écriture. Les échecs réarment la stabilité. | Mémoire distincte pour les placements directs, maintien de la mémoire historique à 30 s, stabilité sur écritures abouties seulement. |

## Ce qui est confirmé et ce qui reste inconnu

- U1 : le retard réel de publication de la taille n’est pas mesuré. Les bornes 300 ms / 2 s sont des choix fonctionnels testables, pas des mesures de l’incident.
- U2 : l’utilisateur confirme un redimensionnement à la souris sur un bord. Le bord exact n’est pas identifié. Les tests reproduisent deux chemins défectueux ; ils ne prouvent pas lequel a causé son incident.
- U3 : la projection conserve les membres vivants, les absents sous grâce de 15 s et les stages vides nommés. Les destinations des autres bureaux reposent sur leur état persistant, sans simuler un relevé vivant absent.
- U4 : la matérialisation conserve la place dans le scope hôte. Le retour reste possible après 60 s ou une nuit si le placeholder `.parked` correspondant existe encore dans le bureau/écran d’origine, reconnu par identité physique ou logique. Une ancienne copie `.restored` sans ce témoin reste où elle est. Les `.parked` conservent leur repli historique sans placeholder. Un déplacement explicite vers un écran détache le stage et efface son origine. Les renommages et changements de mode faits pendant l’absence sont conservés.
- U5 : six commandes échouent dans la séquence diagnostiquée : un focus et cinq masquages. On compte 128 passes en 33,577 s, pour la même génération 354, dont 110 échéances de stabilité et 16 passages de sécurité. La cause du refus d’accessibilité n’est pas prouvée. La correction borne ses effets.
- U6 : aucun nouveau type d’événement ni catalogue de diagnostic n’est nécessaire par défaut.

## Choix écartés

- Table de quatre gestes : la seule interaction souris active suffit ; garder une session remplaçable évite l’état inutile.
- Délai global du scheduler ou lecture AX bloquante : cela pénaliserait les interactions saines.
- Numéro visible seulement après fondu : le repère doit rester constant.
- `orderedStageIDs` persistant : il dupliquerait l’ordre existant et ne préserverait pas mieux un placeholder modifié.
- Réutilisation exclusive de `failedFrames` : son expiration historique de 30 s est contractuelle et ne suffit pas pour stopper une boucle durable de placements directs.
- Compteur global ou throttle : une fenêtre refusant l’écriture ne doit pas ralentir les autres.

## Preuves et validation en cours

- /private/tmp/roadie-029-delayed-red-tests.log : reproduction rouge des reprises différées, avec 18 essais en mode libre pour une limite attendue de 2.
- /private/tmp/roadie-029-parking-review-red-tests.log : trois tests rouges, six constats sur les cas de parking relevés en revue.
- Avant les derniers compléments, 47 nouveaux tests ciblés passaient. Une exécution globale de 1 505 tests avait un échec lié à la configuration personnelle d’une fixture. La fixture reçoit désormais une configuration explicite sans workspaces ; les traces temporaires ont été retirées.
- /private/tmp/roadie-029-stage-identity-red-tests.log : quatre tests rouges, cinq constats sur les noms automatiques et les destinations vides personnalisées. La correction capture le type de nom avant détachement, adapte seulement un nom automatique à l’identifiant final et réserve un nouvel identifiant si la destination vide est personnalisée.
- Avant le premier essai utilisateur : 1 514 tests Swift dans 162 suites, tous verts en 8,422 s. Journal : /private/tmp/roadie-029-final-tests.log. Les 26 tests des scripts passent en 23,555 s. Les constats fonctionnels des quatre premiers tours de revue sont traités. L’installation initiale a ensuite été testée par l’utilisateur, sans résultat concluant pour le redimensionnement.

Une progression monotone différée vers une cible n’est pas un nouveau geste et garde le budget de refus. Un geste confirmé puis traité le libère. Un clic simple ne renouvelle ni génération ni budget. La stabilité ne s’arme que sur les écritures abouties, pour toutes les commandes. Aucun nouveau champ persistant n’a été ajouté.

Le parent exécute les preuves rouges puis vertes et conserve les résultats. Les tests couvrent les échecs au-delà de 30 s en modes libre et `spatialBsp`, puis la reprise après changement réel. La validation finale porte sur l’installation réelle. Aucune réussite de test n’est annoncée dans cette recherche avant exécution centralisée.

## Reprise sur l’incident observé

À 05:41:38 CEST le 15 octobre, `layout_external_change_reverted` ramène la largeur de la fenêtre 75411 de 1 055 à 1 382 points. Le tick AX précède le callback `mouseUp`. Le harnais gardait `currentGesture`, mais le runtime ne vérifiait que les boutons physiques. La garde commune `UserInputActivity.blocksLayout` réunit désormais les deux conditions dans le scheduler et le mainteneur. Preuve rouge : /private/tmp/roadie-029-release-race-red-tests.log, un test et six constats ; le même cas passe après correction.

Une autre reproduction montre que le premier intérieur inéligible peut être une bordure décorative située derrière son parent dans l’ordre CG. Des poignées à 0,836 et 4,188 points du cadre étaient ignorées. Le picker limite les poignées aux fenêtres devant cet intérieur ; un vrai obstacle devant continue à bloquer. Les anciens points à y = -300 touchaient le bord exclu de l’obstacle ; les nouvelles fixtures à y = -350 et les coordonnées réelles reproduisent le défaut : /private/tmp/roadie-029-picker-red-tests.log, huit tests et quatre constats. Le focus strict ne change pas.

Les événements `window_gesture_target` ajoutent premier intérieur, application, scope et statut de candidat, sans titre. La nouvelle suite complète passe : 1 520 tests dans 163 suites, en 8,889 s. Journal : /private/tmp/roadie-029-resize-followup-full-tests.log. Les scripts n’ont pas changé ; leurs 26 tests passaient en 23,555 s lors du contrôle précédent.

La revue ciblée 5 est terminée sans blocage prouvé. Le garde-fou de callback perdu est vérifié en rouge puis en vert : /private/tmp/roadie-029-release-recovery-red-tests.log contient 20 tests dans une suite et 16 constats sur la baseline sans récupération ; /private/tmp/roadie-029-release-recovery-full-tests.log confirme 1 526 tests dans 163 suites, tous verts en 7,170 s. Après le premier relâchement physique observé, un seuil de 300 ms autorise la clôture unique du geste et sa consommation par la passe ; un maintien physique ne subit aucun timeout et un callback tardif ne rejoue pas le geste. Ce seuil est consulté par les événements ou le filet périodique existant, sans promesse de délai exact. L’installation finale signée est terminée dans /private/tmp/roadie-029-release-recovery-install.log. Le redémarrage est terminé, daemon PID 60128, et les quatre contrôles de santé passent : /private/tmp/roadie-029-release-recovery-health.json. Le certificat et la configuration sont conservés. Le nouvel essai utilisateur reste attendu. Aucun résultat manuel positif n’est encore confirmé pour cette reprise.
