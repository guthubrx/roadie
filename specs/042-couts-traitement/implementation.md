# Journal de validation

## T002 — BSP et recherche
- Parcours de remplacement en une passe, sans rééquilibrage ni changement des ratios.
- Textes préparés par cible, alignés lors de la fusion des lots ; partition stable des résultats.
- Relecture du diff : suppression des recherches récursives répétées et des normalisations par frappe. Aucune dépendance ajoutée. Cache borné à 500 éléments.
- Tests ciblés BSPTree et TargetSearchModel exécutés avec deux tâches de compilation, sans benchmark. Équivalence sur chaîne de 80 feuilles, suppression, cible absente et lots avec identifiants répétés.
- Limite : pas de mesure de gain temporel sur la machine chargée.

## T003 — Secours AX
- Cache lié à l’index du lot, y compris les lectures indisponibles. Réinitialisé à la réénumération.
- Cadre actualisé par la relecture après écriture, supprimé si l’écriture échoue. Titres lus par l’interface injectable existante.
- 17 tests AX passent. Quatre cibles absentes et trois candidats : trois lectures de cadre et trois de titre, aucune écriture. Test distinct : un cadre modifié ne peut plus résoudre une autre cible par son ancienne position.
- Relecture : unicité, candidats réservés et quarantaine conservés. O(k·m) comparaisons en mémoire restent possibles ; les échanges AX sont bornés à O(m+k). Aucun cache permanent ajouté.
