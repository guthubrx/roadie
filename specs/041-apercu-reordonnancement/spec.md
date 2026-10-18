# 041 — Aperçu du réordonnancement dans le rail

Validée par l’utilisateur le 18 octobre 2026 (« go »). Revue indépendante autorisée.

Pendant le glisser droit d’une stage, montrer ses fenêtres en transparence à leur future place dans le rail. Les autres cartes montrent leur ordre futur. Le relâchement applique cet ordre. Le clic droit simple conserve son menu.

## Critères d’acceptation
- Le trait bleu et la vignette de stage attachée au curseur sont remplacés par cet aperçu.
- Les zones de dépôt restent fixes pendant le geste : aucun saut de destination sous un curseur immobile.
- La géométrie, les légendes, les noms personnalisés et les stages vides respectent le rendu normal.
- Sortir du rail ou annuler restaure les cartes sans changer l’ordre enregistré.
- Le glisser gauche des fenêtres reste inchangé. Aucune écriture d’état pendant l’aperçu.

## Extension validée pendant la session

L’utilisateur demande une aimantation réglable et choisit explicitement de stabiliser la destination de l’aperçu, sans attirer le curseur. Ajouter dans Paramètres > Rail un curseur « Aimantation du réordonnancement (%) », de 0 à 100, défaut 50. Une intensité élevée impose de dépasser davantage la séparation avant de changer de destination. À 0, comportement sans stabilisation. Le dépôt reprend la destination affichée, y compris dans la zone de tolérance. Le réglage suit le rechargement dynamique existant et ne modifie pas l’attraction du bord du rail.
