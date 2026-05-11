<!-- SPECKIT START -->
Current SpecKit feature: `006-pin-popover-collapse`.

For additional context about technologies to be used, project structure,
shell commands, contracts, and architectural decisions, read:

- `specs/006-pin-popover-collapse/spec.md`
- `specs/006-pin-popover-collapse/plan.md`
- `specs/006-pin-popover-collapse/research.md`
- `specs/006-pin-popover-collapse/data-model.md`
- `specs/006-pin-popover-collapse/contracts/`
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
