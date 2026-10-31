# Analyze — 144

2026-10-31. Protocole speckit-analyze exécuté en lecture seule sur les artefacts, puis correctifs documentaires autorisés par my-specify-all et deuxième lecture.
Le script officiel refuse le préfixe session- du nom de branche utilisateur ; relancé avec SPECIFY_FEATURE=144-effets-reglables, sans changer la branche ni les scripts. Hooks de commit facultatifs ignorés : my-specify-all réserve les commits à la livraison.

| ID | Sévérité | Emplacement | Constat | Correction |
|---|---|---|---|---|
| A1 | HIGH | ancien spec, clarification finale | ancien texte excluait le déplacement de source alors que le reflow le nécessite | supprimé au profit du cadrage approuvé et du prototype |
| A2 | HIGH | plan, contrat ApplyResult | un résultat asynchrone ne peut annoncer un succès synchrone | deferred explicite, T016/T018 tests et consommateurs |
| A3 | MEDIUM | tasks T004 | ADR 022 déjà occupé | numéro libre 024 retenu |
| A4 | MEDIUM | réussite | coût GPU sans méthode disponible | T023 constate l’outil ou nomme mesure indisponible ; aucun chiffre inventé |
| A5 | MEDIUM | défauts | désactivation nouvelle ne conserve pas les animations UI historiques | compatibilité des anciens fichiers et cadres conservée ; animations globales désactivées par défaut, changement visuel assumé et documenté |

## Couverture
| Exigence | Tâches |
|---|---|
| FR-001 | T005 T006 T008 T009 T017 |
| FR-002 | T007 T010 T011 T018 |
| FR-003 | T012 T014 T015 T019 |
| FR-004 | T012 T013 T015 |
| FR-005 | T012 T016 T017 T018 T019 |
| FR-006 | T008 T010 T017 T019 |
| FR-007 | T020 T023 T024 T027 |
| FR-008 | T004 T006 T010 T023 |
| SC-001 | T005 T006 T008 T009 |
| SC-002 | T012 T013 T019 |
| SC-003 | T015 T023 |
| SC-004 | T008 T017 T023 |
| SC-005 | T026 T027 T028 |

13 exigences/critères, 28 tâches, couverture 100 %, aucune tâche hors périmètre (gates et livraison inclus), aucune duplication non arbitré. Articles XIX/XX : calcul commun à quatre usages, pas de framework backend ni capture supplémentaire. Aucune violation constitutionnelle non justifiée.
Deuxième lecture : aucun CRITICAL ou HIGH documentaire persistant. Les risques de capture sémantique et de résultat différé restent à vérifier par les tâches de code, pas déclarés résolus par l’analyse documentaire.
