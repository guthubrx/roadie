# Analyze — reprise 10 novembre 2026

Primitive speckit-analyze appliquée : prérequis JSON valides, spec/plan/tasks/reuse-audit
lus, checklist exigences 16/16, hooks analyze uniquement optionnels non exécutés.

| ID | Gravité | Constat | Correction |
|---|---|---|---|
| A1 | HIGH | Ancien contrat artifacts-only incompatible avec demande actuelle | Contrat actif prioritaire sur six artefacts et FR-025–030 |
| A2 | HIGH | D1/D2/D3/D4/D8 non couvertes dans 45 tâches | T046–053 ajoutées |
| A3 | HIGH | FR-005 sans contrôle dirty et tests réseau limités à evaluate | T049 transport + dirty |
| A4 | MEDIUM | Test config par défaut exclut nil/tableaux vides | T049 valeurs peuplées |
| A5 | MEDIUM | R0 préparatoire interdit de diagnostiquer un défaut réel | Contrat actuel autorise corrections ciblées et recontrôle |

Deuxième lecture : aucun CRITICAL persistant ; 30 exigences couvertes, aucune nouvelle
abstraction sans besoin ; 53 tâches dont 45 existantes. Exclusions : CI distante non lancée,
compte Apple, Intel, réécriture historique. Le code reste à vérifier par Converge et audit.
