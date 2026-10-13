<!-- SPECKIT START -->
Current SpecKit feature: `021-target-search-mode`.

Contexte :
- `specs/021-target-search-mode/spec.md`
- `specs/021-target-search-mode/plan.md`
- `specs/021-target-search-mode/research.md`
- `specs/021-target-search-mode/data-model.md`
- `specs/021-target-search-mode/contracts/`
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
