# Session 028 — Recherche des contrôles et fermeture au clic extérieur

Statut : clôturée, installée et validée le 14 octobre 2026.
Tests : 18/18 tests dédiés passent ; suite complète : 1 458 tests.

## Besoin

Le dossier Drafts est visible dans Outlook mais la recherche « draft » affiche zéro
résultat. La barre doit se fermer lorsque l’utilisateur clique ailleurs.

## Comportements attendus

- R1 : diagnostiquer les contrôles exposés par Outlook ; conserver le libellé des
  contrôles natifs qui le portent dans un enfant, avec leur véritable cible.
- R2 : lire les contrôles visibles sans épuiser le budget dans les lignes hors
  écran. Garder une collecte bornée et les garanties existantes des cibles web.
- R3 : un clic hors de la barre et de son panneau ferme recherche ou commandes.
  Le clic atteint normalement l’application. Un clic intérieur laisse la barre.
- R4 : la fermeture annule toute activation différée et libère les observateurs.
  Les réponses asynchrones anciennes ne rouvrent pas la barre.

## Validation

Tests Swift Testing pour libellés natifs, limites de collecte, géométrie sur
plusieurs écrans, commandes et annulation. Installation puis essai dans Outlook :
« draft » doit identifier Drafts ; un clic extérieur doit fermer la barre sans
bloquer l’application. Les autres modes de navigation restent fonctionnels.

## Périmètre

Réutiliser les services AX, le modèle de recherche et le dessin AppKit existants.
Aucune dépendance, nouvelle version ou publication. Ne pas modifier la
configuration personnelle ni les permissions macOS pour contourner le diagnostic.
