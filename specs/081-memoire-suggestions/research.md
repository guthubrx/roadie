# Recherche 081

## R1 Où noter les déplacements
Deux chemins : `WindowContextActions.assign` (barre, menu de titre, projets) et
`StageCommandService.assign` (rail, vue d'ensemble, CLI), qui émettent `stage_assign_window`. Le
journal d'événements est tournant (≈ 1 Mo) et ne porte pas l'application : le relire à chaque
ouverture coûterait. Un fichier dédié borné (200) est écrit au déplacement, rare.

## R2 Fenêtre précédente
`WindowSwitcherFocusHistory.shared.recentIDs` (sélecteur, SPEC-056) : ordre d'usage récent. La
première différente de la fenêtre active et connue des cibles de la barre.

## R3 Fermées récemment
`PersistentStageMember.confirmedClosedAt` (SPEC-029) reste jusqu'à la purge (30 min sans relance)
ou au remappage après relance. Rouvrir = « Ouvrir dans… » cette stage (placement 074) : une
application relancée retrouve souvent ses documents par la restauration de macOS.

## R4 Règle
`WindowRuleAffinityService.saveAffinity(kind: .app, …)` crée « Toujours ouvrir cette app ici » et
garde le choix de tuilage (075). Une affinité existante pour cette application vers cette stage
empêche la proposition.
