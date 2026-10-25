# Contre-revue adverse 075

- Date : 2026-10-25. Demande : `bridget_auto_delegate`, request_id `roadie-075-plan-review-1`,
  revue du plan en lecture seule (règle unique R4, extension de `confirm`, raccourci, tests).
- Résultat : refus d'admission `routing_candidate_unavailable` (`capability_unavailable` sur 18
  candidats, `permissions_changed` sur 10), aucune tâche enregistrée. `bridget who` : aucun agent
  connecté.
- Contre-revue indisponible ; remplacée par une relecture ciblée des points demandés :

| Objection examinée | Vérifiée comment | Retenue | Raison |
|---|---|---|---|
| Deux règles pour une même application s'annulent | `WindowRuleEngine.evaluate`, `DaemonSnapshot` `firstMatch` | oui | règle unique `affinity-app-…` |
| Une règle utilisateur de priorité supérieure masque le choix | priorité 9 000, tri décroissant | non | voulu : la règle écrite à la main prime |
| `confirm` étendu casse le tap CGEvent | init `SearchKeyInput(keyCode:…)`, tests `TargetSearchModelTests` | non | valeurs par défaut, 1 983 tests |
