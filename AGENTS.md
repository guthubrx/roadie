<!-- SPECKIT START -->
Current SpecKit feature: `005-window-pins`.

For additional context about technologies to be used, project structure,
shell commands, contracts, and architectural decisions, read:

- `specs/005-window-pins/spec.md`
- `specs/005-window-pins/plan.md`
- `specs/005-window-pins/research.md`
- `specs/005-window-pins/data-model.md`
- `specs/005-window-pins/contracts/`
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
