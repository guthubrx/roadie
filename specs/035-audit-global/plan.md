# Plan

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

1. Figer les sources combinées et identifier les entrées et invariants.
2. Scanner les fichiers et l'historique, compiler, lire les chemins critiques.
3. Reproduire et corriger les défauts non ambigus en trois passes maximum.
4. Rechercher les variantes et exécuter les tests avec les mêmes données.
5. Créer un état final figé, relancer les contrôles pertinents et calculer le rapport V15.

Le code préexistant de la livraison combinée est distinct des corrections de l'audit. Aucun refactoring massif de placement ne sera introduit sans preuve d'équivalence.
