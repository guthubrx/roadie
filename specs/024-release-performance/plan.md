# Plan — session 024

## Contexte technique

Swift 6, macOS 14+, Swift Testing et modules RoadieStages/RoadieDaemon existants.
Sources de départ : `d2e7daf0`. Aucun format persistant ni contrat CLI modifié.

## Diagnostic et décisions

1. PERF-010 : `SnapshotService.reconcile` reconstruit un `RoadieState` neuf avec
   `assignWindow` répété. Grouper les affectations puis écrire chaque stage une fois.
   Garder l'API de déplacement pour les vrais déplacements et restaurer le focus ensuite.
2. PERF-011 : collecter les scopes admissibles dans un Set avant toute validation
   d'intent. La validation géométrique et ses règles restent identiques.
3. PERF-012 : exclure une fois les candidats réclamés au début de la passe. Construire
   un index géométrique éphémère par signature. Chercher les deux meilleurs scores
   sans tri par membre et retirer les candidats réattribués. Les refus de proximité,
   d'ambiguïté et de PID vivant restent inchangés. Documenter les cas dégénérés.

## Réutilisation

Les structures `RoadieState`, `StageState`, `StageScope`, `SnapshotService`,
`PersistentStageState`, `StableWindowSignature`, `frameDistance`, `LayoutIntent`
et le validateur `hasValidLayoutIntent` restent les autorités existantes.
L'index géométrique n'est ni un service ni un cache durable ; sa durée est une passe.

## Validation

Comparer l'ancien comportement aux nouvelles fonctions sur fixtures déterministes.
Mesurer 50, 100, 200 et 400 fenêtres/membres avec les mêmes données et la même
configuration de compilation. Cas couverts : ordre et doublons, plusieurs scopes,
focus/groupes/épinglages, modes et stages inactifs, ambiguïté, seuils exacts,
PID vivant, tous candidats déjà réclamés et unicité des remplacements.

Revue indépendante autorisée par l'utilisateur, puis suite Swift complète et
tests des scripts. Rapporter les limites des mesures. Mettre à jour le dossier
de release, sans modifier les rapports historiques.

## Gates

Constitution globale, standards de tests et qualité lus. Architecture locale
conservée, aucune dépendance. Mesures et revue nécessaires avant clôture.
