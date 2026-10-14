<!-- SPECKIT START -->
Session 029 implémentée le 2026-10-14 : fermeture confirmée propagée au StageStore,
grâce transitoire de 15 secondes conservée, cible p95 inférieure à 400 ms.
Tests ciblés : 117 succès. Suite complète : 1466 succès. Revue finale approuvée.
Audit v14 : A, aucun finding, validateur conforme. Build Release installé et signé.
Runtime Roadie actif sur le PID 93111. Une fermeture réelle a produit le marqueur
`confirmedClosedAt` et un rafraîchissement du rail 90 ms après la détection.
Source 94e15e7cc6d5b682329a5efb9fe697f1ed938db9 intégrée par
4b1f4171564997355c99f09bf659b405cf12c09e et poussée sur origin/main.
Artefacts : specs/029-navrail-fermeture/. Reçu :
specs/029-navrail-fermeture/validation/livraison029.md.
Current SpecKit feature: `029-navrail-fermeture`.

Contexte :
- `specs/029-navrail-fermeture/spec.md`
- `specs/029-navrail-fermeture/plan.md`
- `specs/029-navrail-fermeture/research.md`
- `specs/029-navrail-fermeture/tasks.md`
<!-- SPECKIT END -->

<!-- SPECKIT-USER START -->
# Couche utilisateur SpecKit

- Source de verite utilisateur: `~/.speckit/`.
- Avant une feature/refactor structurel: executer ou appliquer `/speckit.sync`.
- Charger `.specify/memory/constitution.md` pour les gates projet.
- Charger `.specify/memory/standards.md` pour retrouver les refs et baselines research.
- Ne pas modifier directement `.agents/skills/speckit-*`, `.specify/templates/*`, `.specify/scripts/*` ou `.specify/workflows/*`.
- Les commandes utilisateur canoniques vivent dans `~/.speckit/commands/` et sont publiees vers Codex/Claude/Gemini par `~/.speckit/scripts/sync-agent-adapters.py`.
<!-- SPECKIT-USER END -->
