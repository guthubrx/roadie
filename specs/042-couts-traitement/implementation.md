# Journal de validation

## T002 — BSP et recherche
- Parcours de remplacement en une passe, sans rééquilibrage ni changement des ratios.
- Textes préparés par cible, alignés lors de la fusion des lots ; partition stable des résultats.
- Relecture du diff : suppression des recherches récursives répétées et des normalisations par frappe. Aucune dépendance ajoutée. Cache borné à 500 éléments.
- Tests ciblés BSPTree et TargetSearchModel exécutés avec deux tâches de compilation, sans benchmark. Équivalence sur chaîne de 80 feuilles, suppression, cible absente et lots avec identifiants répétés.
- Limite : pas de mesure de gain temporel sur la machine chargée.
