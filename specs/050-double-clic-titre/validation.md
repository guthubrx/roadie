# Validation - 050 Double-clic sur la barre de titre

Date : 18 octobre 2026. Branche : session-050-double-clic-titre (rejouée au-dessus de la 049).

- Rouge : compilation des tests en échec avant code (`MacOSDoubleClickAction` absent).
- Tests 050 : action macOS lue, décision du double-clic, éléments interactifs et fenêtres
  flottantes refusés, réglage décodé, conflit signalé par la santé, régression de geste
  (`Spec050DoubleClickGestureTests`, issue de l'audit). Chaîne complète : 1 744 tests / 208 suites.
- Revue (Claude Haiku 5.5) : APPROVE_WITH_CHANGES. Retenu : refus des éléments interactifs
  (champs, boutons, onglets, liens, contenu web) et des fenêtres flottantes, relevé frais, garde
  en double retirée.
- Audit V15 : `audits/2026-10-18/session-2026-10-18-050-v15-double-clic-titre-01/`, décision
  **inconclusive** (historique ciblé hors adaptateur, sans fuite, option A). Retenu : réglage
  désactivé par défaut (sinon `warn` pour toute personne au réglage macOS d'origine),
  commentaire de documentation déplacé, régression de geste ajoutée.
- Installation : UUID 7FAEFA94-B08E-3C14-B9B4-852B532C97E3, PID 1128 ; santé `ok`.
- Non vérifié en réel : double-clic (réglage désactivé par défaut ; l'utilisateur garde l'action
  macOS d'origine). Pour l'essayer : `double_click_maximize = true` et macOS « Ne rien faire ».
