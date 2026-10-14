# Feature Specification: Corrections de l'audit v14 complet

**Branche** : `022-audit-remediation` | **Créée** : 2026-10-13 | **Statut** : intégration dans main ; remédiation complète non atteinte

Voir le journal `implementation.md`. Le troisième audit conserve 15 constats actifs, dont 3 HIGH.
La fusion ne valide donc pas le critère SC-001 ni la clôture complète de cette spécification.

## Constat de départ

L'audit v14 du dépôt entier (`audits/2026-10-13/full-codebase-01/scoring.md`, note B+ 83,16/100,
fiabilité F) liste 50 constats : 7 HIGH, 38 MEDIUM, 5 LOW. Les 7 HIGH bloquent la validation v14.
L'utilisateur demande de corriger **tous** les constats.

## User Scenarios & Testing

### User Story 1 - Roadie ne plante pas et ne perd pas d'état (P1)
Une commande mal formée est refusée proprement ; `state heal` ne détache pas une fenêtre réduite ou
masquée ; une mutation qui n'a pas pu être enregistrée n'annonce pas de succès.

### User Story 2 - La cible activée est la cible affichée (P1)
Le mode lettres active exactement la cible dont la lettre a été tapée ; un clic sur une autre
fenêtre n'est pas envoyé si cette fenêtre n'a pas pu passer au premier plan.

### User Story 3 - Les commandes multi-écrans et multi-bureaux font ce qu'elles disent (P2)
Écran, bureau, stage, largeur, parking d'écran, focus souris, rails et règles de placement suivent
l'écran et le bureau demandés.

### User Story 4 - Pas de coût quadratique ou cubique évitable (P2)
Les chemins de disposition, d'aperçu de dépôt et de réparation n'effectuent plus de recherches
linéaires répétées dans des boucles.

### User Story 5 - Code plus court, tests utiles, doc exacte (P3)
Duplications et helpers recopiés supprimés ; tests qui vérifient le comportement utile ; guides
alignés sur le code.

## Requirements

- **FR-001** : chaque constat de `audits/2026-10-13/full-codebase-01/cycle-1/aggregated-findings.json`
  MUST être corrigé, ou rejeté avec une justification écrite et vérifiée (faux positif démontré).
- **FR-002** : chaque correction de fiabilité MUST avoir un test qui échoue avant et passe après,
  sauf impossibilité documentée (frontière système non simulable).
- **FR-003** : chaque correction de performance MUST garder les résultats identiques (test de
  non-régression) et documenter la complexité avant/après (Article XVIII) ; un gain annoncé MUST être
  mesuré (Article XXII) ou présenté comme une réduction de complexité prouvée par lecture.
- **FR-004** : aucune régression : `swift build` et `swift test` complets verts.

## Success Criteria

- **SC-001** : 0 constat HIGH restant ; nouvel audit v14 sans blocage.
- **SC-002** : suite complète verte, nombre de tests en hausse.
- **SC-003** : comportement visible inchangé hors corrections (validation utilisateur sur Roadie installé).
