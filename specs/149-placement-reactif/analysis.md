# Relecture locale 149

## Corrections vérifiées
- Remontée des résultats finaux avec génération du lot : aucune image intermédiaire prise pour une fin. Le permis rejette les retours des anciennes sessions.
- La mémoire des échecs et les diagnostics existants reçoivent les retours animés ; la sélection des commandes écarte le même échec tant que son cadre et sa cible restent identiques.
- Acquisition producteur sérialisée, validations avant publication et à la reprise ; une demande reçue pendant l’attente reste en attente. Le rejeu conserve le relevé de la passe, y compris la lecture de focus.
- Fin de processus : annulation de la tâche de préparation avant toute publication tardive. Ouverture de barre annulée : moniteurs retirés, chronométrage fini, raccourcis BTT rétablis.
- Les métriques AX commencent avant l’acquisition ; le temps d’observation est séparé du temps de décision sur le fil principal. Un total AX global peut inclure les écritures concurrentes, ce n’est pas du temps CPU.

## Minimalisme et responsabilité future
Checklist : pas de dépendance ; aucune nouvelle option utilisateur ; réemploi du readerSnapshot, du writer et de la mémoire d’échec ; extraction showTargetsSearch nécessaire à la frontière d’attente ; aucun second pipeline d’arbre. Suppression du booléen préparant redondant avec la tâche et du double arrêt du chronomètre. Potentiel minimalisme résiduel : environ0ligne démontrée supprimable à comportement constant dans les ajouts relus. Les petits champs de temps servent les métriques distinctes.
Le volume ajouté est principalement constitué des régressions ciblées et du cycle de vie asynchrone. Il évite de répéter les traitements et rend les erreurs attribuables à une fenêtre. Il ajoute une attente annulable à comprendre ; la frontière MainActor et la génération sont explicites. Aucun résultat indépendant n’est déduit de cette relecture locale.

- L’échantillonnage pendant l’application fictive lente identifie aussi une lecture d’identité dans le callback AX. La relecture de cadre est maintenant coalescée par fenêtre en arrière-plan. L’identité connue reste locale ; les tâches sont annulées sur destruction et arrêt, et une ancienne génération ne confirme pas le refus d’une nouvelle écriture.

## Limites
Les applications peuvent toujours refuser un cadre ou répondre lentement. Le clavier natif ne peut pas être piloté dans cet environnement ; des ouvertures réelles par commandes et une application fictive lente servent aux comparaisons. Aucun document, titre utilisateur ou trace privée n’est publié.
