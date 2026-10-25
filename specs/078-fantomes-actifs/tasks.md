# Tâches 078

## US1 Disposition future (P1)
- [x] T001 Tests puis `previewPlacements` (arbre et autres moteurs, fantôme ou fenêtre réelle).
- [x] T002 `LayoutPreviewHold` et sortie tôt de `LayoutMaintainer.tick(cause:)` ; tests d'échéance.

## US2 Aperçu en direct (P1)
- [x] T003 Contrôleur : début (bascule si stage cachée du bureau affiché, maintien, écriture des
  cadres, fantôme), renouvellement, fin avec ou sans restauration ; journal `launcher.preview`.
- [x] T004 Barre : demande à 150 ms selon la ligne, fin à Échap, retour d'étape, autre ligne et
  fermeture ; validation par Retour ; fantôme dessiné dans l'overlay.

## Livraison
- [x] T005 Suite complète, installation, santé, essai réel par `roadie launch --here --preview-only`
  (aperçu puis fin : cadres identiques à 2 points), docs FR/EN, CHANGELOG, validation. Essai au
  clavier : utilisateur (limite notée).
