# Session 030 — Récupération des fenêtres au démarrage

Statut : En cours. Validation utilisateur : 2026-10-15.

## Problème prouvé

Après un redémarrage avec l'écran externe absent, T3 (52803) et Firefox
(17115) restent membres de cet écran dans l'état persistant. Le relevé leur
attribue un scope nul en attendant une récupération déclenchée seulement par
une notification d'écran. Le placement et le navrail ignorent ces fenêtres.

## Comportement attendu

- Récupérer les fenêtres vivantes d'un écran absent après stabilisation des écrans.
- Fonctionner au démarrage sans notification et si les fenêtres arrivent plus tard.
- Préserver les groupes, les métadonnées de retour et les membres temporairement absents.
- Ne rien migrer sans permission Accessibilité ou avec un relevé vide.
- Ne créer aucun doublon lors des passes suivantes.

Tests : reproduction par le vrai LayoutMaintainer avec fournisseur système isolé,
régression du parking, suite Swift complète, installation signée et redémarrage réel.
