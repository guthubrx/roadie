# Contre-revue du plan — passage 1

**Décision :** BLOCK, traité le 2026-10-14.

## Objections retenues

- La cible p95 de 250 ms ne couvrait pas le watcher et le rendu monolithique.
- Une seule passe ne suffit pas si CoreGraphics garde brièvement l'identifiant.
- Une preuve sans date peut supprimer plus tard une fenêtre seulement masquée.
- Le retrait doit nettoyer aussi le focus précédent.
- Les mesures doivent distinguer les modes monolithique et modulaire.

## Réponses

- La cible passe à 400 ms au p95.
- Une échéance de 50 ms est ajoutée, avec dix reprises au maximum.
- La preuve d'appartenance expire après cinq secondes.
- Une opération dédiée du `StageStore` nettoie membre, groupes et deux focus.
- Le plan demande les deux mesures et documente toute architecture non activable.
- La terminaison complète d'une application sort du périmètre. Elle conserve
  ainsi le contrat de restauration de SPEC-016.

## Objections documentées sans changement structurel

- L'API actuelle du `StageStore` ne confirme pas l'écriture. Le filet de
  sécurité reste le repli en cas d'échec rare.
- Pins, signets et surcharges gardent leurs grâces. Ils ne sont pas affichés
  dans le navrail.
