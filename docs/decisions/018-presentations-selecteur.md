# ADR 018 - Présentations du sélecteur

Date : 2026-10-23. Statut : Accepté.

Le sélecteur propose des styles de carte mais une seule grille. L'utilisateur
demande les cinq organisations montrées dans les maquettes, choisies dans les réglages.

Décision : une organisation commune, surchargeable par profil, et un seul panneau.
Le calcul pur des groupes et des cadres réutilise les résultats filtrés ; AppKit
rend les cartes, groupes et contrôles. Les identités incluent écran/bureau/stage.
La sélection globale, les actions et la capture d'images restent partagées.

Conséquences : aucune acquisition supplémentaire ni nouvelle dépendance. Les cinq
vues restent cohérentes avec les styles et le rechargement existants. La géométrie
et le passage de sélection entre groupes demandent des tests ciblés. L'ordre des
groupes suit leur première apparition dans les résultats du profil ; ce n'est pas
un réordonnancement des stages persistées.
