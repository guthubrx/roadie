# Validation 100

- Avant correction (test jetable) : `update(text: "")` pendant la composition vidait l'éditeur.
- Après correction : texte marqué `˜` conservé, `~` validé transmis au modèle.
- Tests ajoutés : `Tests/RoadieDaemonTests/Spec100DeadKeyTests.swift` (2 tests) ; avec
  `Spec038NativeInputTests` : 12 tests réussis.
- Essai réel au clavier : à faire par l'utilisateur (événements clavier synthétiques refusés à l'agent).
