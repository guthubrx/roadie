# Revue indépendante du plan

Demande `roadie142-plan-review-20261031-01`, tâche Bridget `b943714d-006a-48b9-b44a-cbcfbcf70beb`, message `296dfd9a-a50f-4cd2-ac29-9782f12957c9`. Réviseur sélectionné par Bridget, lecture seule distante. Source de base b223718f. Verdict : APPROVE_WITH_CHANGES ; aucune mesure native effectuée par le réviseur.

| Objection | Vérification et décision |
|---|---|
| Exclure la fenêtre saisie | Retenue : filtre explicite avant ApplyCommand ; tests de toutes les demandes |
| Définir la source du cadre | Retenue : WindowServer ciblé avec correspondance stricte CG ID/PID, hors MainActor |
| Ne pas ajouter de takeGesture concurrent | Retenue : hook onDragStart et currentGesture ; clôture du seul geste confirmé après sauvegarde |
| Arbre sur MainActor | Retenue : observation et writer seuls hors MainActor ; permission verrouillée |
| Une transaction finale contrôlée | Retenue : mutateChecked avec arbre initial et scope actif |
| Éviter adjustingFence quadratique à chaque mouvement | Retenue : modèle de géométrie préparé, parcours linéaire |
| Réutiliser directement DividerResizeCoordinator | Non retenue telle quelle : il persiste et applique synchrone à chaque flush, avec géométrie de poignée. Le réutiliser ici conserverait le coût et réécrirait la cible. Géométrie BSP, writer, budgets, sessions d’entrée et transaction restent communs. Le runtime natif est justifié par la propriété native de la cible et la clôture différée. |

Limite de la revue : les artefacts non committés n’étaient pas présents dans le checkout distant ; le brief complet servait de plan. Le réviseur n’a pas pu lancer Git ni les tests (shell désactivé). Ses constats ont été confrontés au code local avant intégration.
