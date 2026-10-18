# Plan

Réutiliser StagePresentationOrder, NSScrollView et les tests de géométrie AppKit.
Conserver le rang partagé des destinations et les cibles du dépôt après défilement.
Préserver les origines du parking ; réutiliser les emplacements compatibles plutôt
que déduire une identité depuis les chaînes d'identifiants parked imbriqués.

UserInputActivity conserve la cible issue du dernier relevé sans le rafraîchir au
clic ; un callback unique au premier mouseDragged ouvre l'acquisition nécessaire.
La poignée acceptée efface toujours le geste natif et son callback en attente.

V15 se corrige dans son dépôt existant sans toucher aux modifications étrangères.
Bornes Git résolues en commit, commande sans shell et portée conservée avec la
preuve du scanner. Tester bornes invalides et option réservée à gitleaks-history.

Tests Swift ciblés puis suite complète avec deux tâches, compilation et installation
signées, vérification santé. Preuves visuelles si bureau accessible, sinon limite
documentée ; aucun benchmark de performance sous charge.

Complément de revue : limiter les seuils de réordonnancement aux cartes de même
catégorie que la source (occupées ou vides). La priorité reste ainsi respectée,
et les rangs persistants restent croissants dans chaque catégorie. Reproduire le
cas [vide, A, B] affiché [A, B, vide], puis déplacer A après B. Vérifier aussi
deux vides et l'aperçu concordant avec le dépôt.

Constats complémentaires : aucun relevé pour un glisser sans cible gérée. Effacer
l'ancrage quand la géométrie devient incertaine, tout en le conservant pour un
simple focus de fenêtre qui ne modifie pas ses cadres. Protéger la case vide active
à l'arrivée du parking. Borner la zone de défilement à la hauteur utilisable entre
la barre des menus et le Dock. Tests de reproduction avant correction.
