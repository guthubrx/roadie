# Contrat : événement `targets.app_scan`

Écrit dans `~/.roadies/events.jsonl` par `TargetHintService.list` après chaque parcours applicatif qui a produit des statistiques.

```json
{"type":"targets.app_scan","details":{
  "bundleID":"com.t3tools.t3code","isElectron":"true","manualAccessibility":"enabled",
  "visited":"412","candidates":"57","offscreen":"18","maxDepthReached":"8","atMaxDepth":"31","sawWebArea":"true",
  "elapsedMs":"240","stopReason":"complete","retries":"1"}}
```

Les compteurs (`visited`, `candidates`, `offscreen`, profondeurs, `sawWebArea`, `stopReason`) décrivent la dernière passe ; `elapsedMs` couvre toute l'opération, relances et attentes comprises. Toutes les valeurs sont des chaînes (format existant de `RoadieEvent.details`). L'événement `targets.list` reste inchangé.
