# Session 042 — Réduction des coûts de traitement

Correction autorisée le 18 octobre 2026 (« corrige tout »), après revue statique de f96216c0. Estimation : 2 à 4 heures, validation et installation comprises.

## Résultats attendus
- Les lecteurs graphiques ne déclenchent plus un relevé AX synchrone sur le fil principal. Les demandes concurrentes partagent une acquisition. Les commandes conservent leur contrat de fraîcheur.
- Le rail réutilise l’inventaire du relevé et ne reconstruit pas les écrans inchangés.
- Le secours AX mémorise les attributs par lot, sans réutiliser un cadre invalidé par une écriture.
- Les mutations BSP évitent les recherches répétées dans les sous-arbres ; ordre, ratios et dispositions restent identiques.
- La recherche prépare les textes une fois par cible et classe les résultats en un passage.
- Le réordonnancement prépare sa géométrie et réutilise ses copies pendant le geste.

## Validation
Tests fonctionnels, équivalence et comptages déterministes. Aucun benchmark de durée ni test de charge : la machine est occupée. Aucun gain chiffré annoncé sans mesure. Conserver les budgets AX/captures, quarantaines, gestes, fermeture confirmée et chargement dynamique des réglages. Aucun changement de configuration utilisateur ni nouvelle dépendance.
