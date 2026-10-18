# 041 — Aperçu du réordonnancement dans le rail

Validée par l’utilisateur le 18 octobre 2026 (« go »). Revue indépendante autorisée.

Pendant le glisser droit d’une stage, montrer ses fenêtres en transparence à leur future place dans le rail. Les autres cartes montrent leur ordre futur. Le relâchement applique cet ordre. Le clic droit simple conserve son menu.

## Critères d’acceptation
- Le trait bleu et la vignette de stage attachée au curseur sont remplacés par cet aperçu.
- Les zones de dépôt restent fixes pendant le geste : aucun saut de destination sous un curseur immobile.
- La géométrie, les légendes, les noms personnalisés et les stages vides respectent le rendu normal.
- Sortir du rail ou annuler restaure les cartes sans changer l’ordre enregistré.
- Le glisser gauche des fenêtres reste inchangé. Aucune écriture d’état pendant l’aperçu.
