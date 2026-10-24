# Spécification 063 - Publication de Roadie 0.8.0

Demande du 24 octobre 2026 : commit, intégration, push, publication et nettoyage des
branches, worktrees, binaires et compilations obsolètes.

## Périmètre
Version mineure depuis v0.7.0 : sessions 060 (organisations du sélecteur), 061 (vue
d'ensemble et ses suites T013 à T029), 062 (Mission Control) et correction CLI
`desktop focus next|prev`. Version applicative et défaut du script DMG à 0.8.0 ;
README, guides, index et notes FR/EN alignés ; changelog regroupé.

## Critères
- Suite de tests complète verte (hors instables connus, réussis seuls).
- DMG vérifié (montage, bundle, versions, signature ad hoc, SHA-256).
- `main` avancé, poussé, tag annoté v0.8.0, release GitHub Latest avec DMG et SHA-256
  retéléchargés et identiques.
- Installation locale 0.8.0, santé 5/5, certificat et configuration conservés.
- Branches et worktrees obsolètes supprimés, builds et binaires intermédiaires nettoyés.

## Limites connues
Revue indépendante et audit des sessions 061 et 062 non réalisés avant publication
(T009/T011 de 061) ; relecture indépendante limitée aux textes publiés.
