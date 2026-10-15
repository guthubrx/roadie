# Recherche : session 029

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
| Longue absence | La matérialisation après 60 s ne doit pas empêcher le retour ultérieur. | Garder l’origine et le placeholder correspondants. Reprendre aussi les copies `.restored` qui restent ailleurs que dans leur scope d’origine. |
| Refus répétés | Les placements hors arbre contournent la mémoire utile des refus. Un chemin de focus contourne aussi le budget d’écriture. Les échecs réarment la stabilité. | Mémoire distincte pour les placements directs, maintien de la mémoire historique à 30 s, stabilité sur écritures abouties seulement. |

## Ce qui est confirmé et ce qui reste inconnu

- U1 : le retard réel de publication de la taille n’est pas mesuré. Les bornes 300 ms / 2 s sont des choix fonctionnels testables, pas des mesures de l’incident.
- U2 : le geste exact de l’utilisateur n’est pas identifié. Les tests reproduisent deux chemins défectueux ; ils ne prouvent pas lequel a causé son incident.
- U3 : la projection conserve les membres vivants, les absents sous grâce de 15 s et les stages vides nommés. Les destinations des autres bureaux reposent sur leur état persistant, sans simuler un relevé vivant absent.
- U4 : la matérialisation conserve la place dans le scope hôte. Le retour à l’origine reste requis après 60 s et après une nuit. Les renommages et changements de mode faits pendant l’absence sont conservés.
- U5 : six commandes échouent dans la séquence diagnostiquée : un focus et cinq masquages. On compte 128 passes en 33,577 s, pour la même génération 354, dont 110 échéances de stabilité et 16 passages de sécurité. La cause du refus d’accessibilité n’est pas prouvée. La correction borne ses effets.
- U6 : aucun nouveau type d’événement ni catalogue de diagnostic n’est nécessaire par défaut.

## Choix écartés

- Table de quatre gestes : la seule interaction souris active suffit ; garder une session remplaçable évite l’état inutile.
- Délai global du scheduler ou lecture AX bloquante : cela pénaliserait les interactions saines.
- Numéro visible seulement après fondu : le repère doit rester constant.
- `orderedStageIDs` persistant : il dupliquerait l’ordre existant et ne préserverait pas mieux un placeholder modifié.
- Réutilisation exclusive de `failedFrames` : son expiration historique de 30 s est contractuelle et ne suffit pas pour stopper une boucle durable de placements directs.
- Compteur global ou throttle : une fenêtre refusant l’écriture ne doit pas ralentir les autres.

## Vérification attendue

Le parent exécute les preuves rouges puis vertes et conserve les résultats. Les tests couvrent les échecs au-delà de 30 s en modes libre et `spatialBsp`, puis la reprise après changement réel. La validation finale porte sur l’installation réelle. Aucune réussite de test n’est annoncée dans cette recherche avant exécution centralisée.
