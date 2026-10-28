# Revue indépendante des corrections

Mission Bridget `67a66c3d-4d55-439d-bb7f-8816f83b8914`, demande `roadie-093-review-final-20261027-v1`, relecteur `2c134341-fad9-47fa-903d-e4d22468ac63`. La revue a comparé le diff transmis au commit `5ed75b0532c4179c2b6b7d6a4a88e5e2ec2e92fd`, dans un environnement Linux en lecture seule. Elle n'a exécuté aucun test macOS.

La revue confirme que `.` et `..` sont refusés aux deux points d'entrée et que le verrou de `JSONPersistence.mutate` couvre lecture et écriture. Elle identifie quatre points :

1. Une opération de persistance refusée peut annoncer un succès : `mutate` journalise l'erreur. Traitement : historique, abréviations et projets explicites utilisent `mutateChecked` ; les résultats et événements suivent l'écriture. La commande de projet est asynchrone : son accusé de réception ne prouve pas la persistance.
2. Le test clavier ne contrôlait pas l'absence d'événement. Traitement : l'émetteur est injecté ; le test vérifie zéro événement invalide et deux événements valides, sans émission système.
3. Le remplacement d'un workflow supprimait l'ancien avant le déplacement du nouveau. Traitement : copie préparée sur le volume de destination, échange atomique et test d'échec injecté.
4. Une ancre de classement finie mais extrême pouvait devenir infinie et empêcher l'encodage. Traitement : maintien d'une ancre finie et test des contextes global et local.

Les 34 tests ciblés sur ces corrections sont passés sur macOS dans la révision 7. Le comportement d'échange réel et l'échec injecté ont été testés dans des répertoires temporaires.

Les corrections postérieures à ce rapport nécessitent leurs propres tests et une nouvelle revue. Les liens symboliques d'archives, les interactions réelles et la gestion complète de l'échec de la commande asynchrone restent à qualifier.

## Deuxième revue

Mission `4990a998-42fd-48cf-9178-05888a52da13`, demande `roadie-093-review-final-20261027-v2`, relecteur `bade9b36-4fc1-4aab-b4a2-47907fc4eb89`. La revue a confirmé les contrôles de stockage, l'émetteur de touches et l'encodage du classement. Elle a relevé trois limites : un dossier temporaire d'échange pouvait apparaître dans l'index, une erreur de suppression de projet était seulement journalisée, et le score d'une ancre extrême pouvait encore être infini.

Traitement engagé : exclusion du préfixe temporaire dans l'index et refus de ce préfixe comme identifiant ; journalisation explicite d'un échec de nettoyage ; notification locale en cas d'échec de suppression ; score limité à une valeur finie. La mise en file CLI reste asynchrone : son code de sortie ne prouve pas que l'action ultérieure a réussi. La revue n'a pas vu la variante des tâches d'automatisation, ajoutée ensuite.

## Troisième revue

Mission `fbc4930f-b3d9-4c5a-8f53-703de90e9c3d`, demande `roadie-093-review-final-20261027-v3`, relecteur `c6395d10-3106-4c50-a0bc-1775cee2a064`. La revue a signalé la perte possible d'une modification extérieure au dossier `Tasks` pendant la copie du dossier complet, une course entre installation et suppression de workflow, et une incompatibilité avec les noms déjà utilisés sous le préfixe temporaire.

Après correction, la mise à jour ne remplace que `Tasks` et `LICENSE` et remet le premier élément si le second échoue ; installation et suppression de workflow partagent un verrou ; le temporaire a un niveau de répertoire supplémentaire et ne réserve plus aucun nom utilisateur. Les tests ciblés de la révision 10 vérifient ces trois points. Les interruptions brutales entre les deux échanges restent une limite.

## Quatrième revue

Mission `a26144c9-26c8-4c81-b937-9cc58aad9983`, demande `roadie-093-review-final-20261027-v4`, relecteur `54abbd0a-1791-49a2-9c75-15e1ce5dea3f`. Verdict : aucun nouveau risque de perte de données ou de course confirmé dans les dernières corrections. La revue a vérifié par lecture le verrou commun, le dossier de préparation non indexé, le remplacement limité à `Tasks` et `LICENSE` et le retour arrière du premier échange.

Cette revue porte sur le diff transmis, depuis un environnement Linux en lecture seule. Elle n'a pas exécuté les tests macOS, ni reproduit une interruption entre les deux échanges, ni enregistré de parcours graphique. La commande de projet demeure asynchrone.
