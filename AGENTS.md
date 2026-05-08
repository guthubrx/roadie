<!-- SPECKIT START -->
Current SpecKit feature: `003-roadie-control-safety`.

For additional context about technologies to be used, project structure,
shell commands, contracts, and architectural decisions, read:

- `specs/003-roadie-control-safety/spec.md`
- `specs/003-roadie-control-safety/plan.md`
- `specs/003-roadie-control-safety/research.md`
- `specs/003-roadie-control-safety/data-model.md`
- `specs/003-roadie-control-safety/contracts/`
- `specs/003-roadie-control-safety/quickstart.md`
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
