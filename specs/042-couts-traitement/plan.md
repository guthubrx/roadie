# Plan technique

Swift, AppKit, Swift Testing ; réutilisation des services et des caches existants.

1. Corriger les parcours BSP et la préparation de recherche ; tests des arbres déséquilibrés et du classement incrémental.
2. Mémoriser les observations AX de secours dans le lot, invalidées après écriture ; tests avec lecteurs injectés.
3. Séparer acquisition asynchrone et rendu des lecteurs ; regroupement des demandes par état et mode de suivi. Conserver les commandes synchrones explicites et la réconciliation protégée. Contrôler les appels AppKit sur le fil principal.
4. Réutiliser l’inventaire CG du relevé, isoler les signatures de rendu par écran. Préserver l’entretien des miniatures.
5. Conserver les seuils et copies du réordonnancement pour le geste, avec invalidation à la fin ou au rerendu.
6. Tests ciblés puis suite séquentielle isolée, compilation avec parallélisme limité. Revue si autorisée, installation signée, santé, intégration Git et nettoyage.

Pas de chronométrage comparatif. Les copies et les résultats sont validés par invariants et compteurs. Les optimisations techniques ne changent pas le dessin attendu.
