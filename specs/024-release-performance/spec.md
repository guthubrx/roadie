# Spécification 024 — Corrections de performance avant v0.4.0

**Branche** : `session-024-release-performance` | **Créée** : 2026-10-14 | **Statut** : implémentée, fusionnée et publiée en v0.4.0
**Demande validée** : corriger PERF-010, PERF-011 et PERF-012 avant la release proposée.

## Scénarios utilisateur et tests

### US1 — Construire le snapshot sans réaffectations répétées (P1)
Le snapshot garde les mêmes fenêtres, leur ordre, leur stage, les groupes et le focus.
Étant donné plusieurs affectations dont un doublon, quand l'état neuf est construit,
alors la dernière affectation conserve sa position et aucun identifiant n'est répété.

### US2 — Valider une disposition une fois par scope (P1)
Étant donné plusieurs fenêtres modifiées dans le même stage actif en BSP,
quand le maintainer décide quels scopes font foi, alors chaque scope est validé une fois.
Les stages inactifs et les autres modes gardent leur comportement.

### US3 — Rapprocher les fenêtres sans tris répétés (P1)
Étant donné des anciennes fenêtres homonymes et des nouvelles fenêtres vivantes,
quand les identifiants sont rapprochés, alors les mêmes remplacements sont choisis.
Un PID vivant protège l'ancien membre. Un candidat déjà réclamé reste indisponible.
Les candidats ambigus ne sont jamais forcés.

## Exigences

- FR-001 : modifier uniquement les trois chemins visés, sans nouvelle dépendance.
- FR-002 : garder le score de cadre, le seuil de proximité 360 et l'écart minimal 120.
- FR-003 : conserver focus, focus précédent, groupes, épinglages et unicité des réattributions.
- FR-004 : tests d'équivalence et cas limites avant validation des corrections.
- FR-005 : mesurer des entrées identiques de tailles croissantes avant/après ; publier
  les conditions, résultats et limites, sans confondre microbenchmark et latence de l'interface.
- FR-006 : décrire les coûts moyens et les pires cas réels, sans fausse borne linéaire.
- FR-007 : suite Swift complète verte et revue indépendante des trois corrections.

## Critères de succès

- SC-001 : reconstruction des appartenances en une passe groupée sur un état neuf.
- SC-002 : une validation géométrique par scope admissible, même avec de nombreuses fenêtres modifiées.
- SC-003 : disparition des tris par membre et des scans des candidats déjà adoptés ;
  recherche indexée des deux meilleurs candidats pour les groupes homonymes.
- SC-004 : trois HIGH clôturés par preuves ciblées, sans réécrire l'audit historique
  ni prétendre résoudre ses douze autres constats.
- SC-005 : changelog et brouillon de release reflètent l'état réellement vérifié.

## Hors périmètre

Les douze constats MEDIUM/LOW, les nouvelles fonctions, les changements d'interface,
les permissions macOS et l'installation dans le daemon courant.
