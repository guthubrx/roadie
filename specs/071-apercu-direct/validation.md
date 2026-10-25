# Validation 071

- `Spec071LivePreviewTests` : aperçu des bureaux (renumérotation, autre écran), des
  stages et fenêtres vers de nouveaux contenants, zone sous le dernier bureau, centrage.
- Tests 061, 066, 067 et 070 adaptés (géométrie de référence centrée, rappel `onDrop`).
- Rendus natifs vérifiés sur données fictives après animation : stage déplacée, fenêtre
  vers un nouveau bureau, bureaux réordonnés, fenêtre vers une nouvelle stage ; sonde
  retirée ensuite.
- Suite complète : 1 959 tests / 249 suites réussis.
- Limite : si l'aperçu change fortement la taille des cartes, la place visée suit la
  disposition d'avant le geste, pas celle affichée.
