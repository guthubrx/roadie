# Validation - 049 Réglages macOS qui gênent le tuilage

Date : 18 octobre 2026. Branche : session-049-reglages-macos (rejouée au-dessus de la 051).

- Rouge : compilation des tests en échec avant code (`MacOSWindowSetting` absent).
- Tests 049 : 5 tests verts. Suite de la chaîne complète : 1 744 tests / 208 suites, verts.
- Revue (Claude Haiku 5.5, Bridget ; Codex non routable) : APPROVE_WITH_CHANGES, sans défaut
  propre à la 049 ; aucun consommateur n'exige tous les contrôles `ok`.
- Audit V15 : `audits/2026-10-18/session-2026-10-18-049-v15-reglages-macos-01/`, décision
  **inconclusive** (même cause que la 048 : analyse ciblée de l'historique hors adaptateur, sans
  fuite, option A). Constat LOW : validation manquante, corrigé ici.
- Installation : UUID 7FAEFA94-B08E-3C14-B9B4-852B532C97E3, PID 1128, signature `roadied-cert`.
  `roadie query health` réel : `ok macos-window-settings aucun réglage macOS en conflit`
  (réglages de l'utilisateur tous à 0).
- Non vérifié : changement d'un réglage pendant que le daemon tourne ; défauts macOS d'une clé
  absente (non documentés par Apple).
