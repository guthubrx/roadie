# Session 019 — Maximisation en laissant la place au navrail

Date : 2026-10-12. Branche : 019-navrail-maximization.
Statut de l'implémentation : Implémentée, 11/11 tâches cochées.

## Résultat

Commande toggle maximize et action de menu ciblée. Réservation complète du panneau, même en auto-hide ; restauration par arbre ou placements sauvegardés ; compatibilité des anciens intents ; plans et maintien recalculent le cadre. Protection contre les refus et le focus natif. Capture des nouvelles voisines et reprise après fermeture de la cible.

## Vérification

820 tests dans 89 suites passent. Audit v14 : A ; quatre défauts de fiabilité trouvés, corrigés et testés. Observation non bloquante : la bascule commune dépasse 50 lignes ; pas de refactor cosmétique ni de couche supplémentaire. Convergence manuelle exigence par exigence ; livraison Git/disque/runtime et nettoyage contrôlés séparément après intégration.

## Réutilisation et charge future

Aucun nouveau fichier de production, aucun nouveau service/store/type partagé, aucune dépendance. Deux champs optionnels dans LayoutIntent ; calcul de cadre réservé et restauration communs aux chemins existants. Masquage, stockage atomique, mémoire des refus et plans par scope réutilisés. Les tests initiaux ont révélé un accès privé ; les vérifications ciblées ont révélé et confirmé les pertes de métadonnées avant correction.
