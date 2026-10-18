# Comparaison du redimensionnement — 18 octobre 2026

## Ce qui a été comparé
Deux puis quatre fenêtres, arbre initial identique, écart de 10 points et séparation verticale déplacée de x=500 à x=700. Chaque essai utilise une fixture isolée. Les deux chemins doivent produire les mêmes cadres finaux et les mêmes placements persistés.

- Bord natif : macOS est simulé par la nouvelle taille de la fenêtre manipulée, puis le vrai LayoutMaintainer traite le geste et ajuste les voisines.
- Poignée : la séparation est désignée explicitement ; le vrai DividerResizeCoordinator applique la dernière cible à partir de son relevé préparé.

Le test mesure l'appel final de traitement. Préparation et présentation, événement souris, ordonnanceur, minuteur de 50 ms et appels AX réels sont exclus. Fournisseur et écrivain sont simulés ; transactions StageStore, journaux et E/S disque sont réels. Compilation Debug, machine chargée : moyennes de charge initiales 32,63 / 28,36 / 28,22.

## Résultats partiels
Un échauffement de chaque chemin, sept paires par disposition, ordre alterné. Mesures en millisecondes ; aucune assertion sur un seuil de durée.

| Fenêtres | Chemin | Médiane du traitement | Étendue | Relevés pendant l'appel | Écritures simulées |
|---|---|---:|---:|---:|---:|
| 2 | Bord natif | 1,73 ms | 1,52–1,90 ms | 1 | 1 |
| 2 | Poignée | 0,60 ms | 0,58–0,73 ms | 0 | 2 |
| 4 | Bord natif | 1,92 ms | 1,73–2,18 ms | 1 | 3 |
| 4 | Poignée | 0,65 ms | 0,60–0,79 ms | 0 | 4 |

Les assertions fonctionnelles vérifient les cadres et la persistance dans chaque essai, y compris le benchmark. Le seuil temporel est volontairement absent : la charge de la machine n'est pas une régression du produit.

## Interprétation et décision
Dans ce test, l'appel préparé de la poignée est plus court que la passe native complète. Les deux appels ne font pas le même travail : le bord exige un relevé et une réconciliation ; la poignée réutilise un relevé établi auparavant. Ce coût préalable existe toujours. Le nombre d'écritures est aussi différent : macOS a déjà redimensionné la fenêtre manipulée dans le chemin natif, alors que la poignée demande tous les placements à Roadie.

Ces chiffres ne sont ni un gain de latence AX ni une mesure de fluidité. Le minuteur peut ajouter jusqu'à 50 ms entre les cibles pendant un glisser par poignée ; le relâchement applique la dernière cible immédiatement. Le redimensionnement natif, lui, déplace déjà le bord dans l'application avant le traitement des voisines. Un essai sur un placement final ne compare pas ces deux expériences continues.

Décision : conserver le repère explicite et corriger son affichage. Ne pas annoncer que le produit est plus rapide sur la base de ce test.

## Essai réel restant
Sur deux puis quatre fenêtres de test : alterner les mêmes déplacements par poignée et par bord. Relever le délai entre événement de souris et première position obtenue, le délai après relâchement jusqu'à stabilisation de toutes les fenêtres, les retours en arrière et les écritures refusées. Inclure les deux écrans et l'affichage JankyBorders. Conserver les mêmes applications, limites et charge ; comparer les médianes et p95 de plusieurs gestes. Refaire ce contrôle sur une machine moins chargée.

Le bureau est inaccessible dans cette session ; aucun geste réel ni résultat de latence utilisateur n'est revendiqué. Les fichiers bruts restent hors Git dans /Users/moi/.roadies/diagnostics/2026-10-18-session044/.

Reproduction : `ROADIE_RESIZE_BENCHMARK=1 /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/scripts/test --jobs 2 --filter benchmarkNativeAndExplicitSoftwarePaths`.
