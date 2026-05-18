<!-- SPECKIT START -->
Current SpecKit feature: `009-roadie-target-mode`.

For additional context about technologies to be used, project structure,
shell commands, contracts, and architectural decisions, read:

- `specs/009-roadie-target-mode/spec.md`
- `specs/009-roadie-target-mode/plan.md`
- `specs/009-roadie-target-mode/research.md`
- `specs/009-roadie-target-mode/data-model.md`
- `specs/009-roadie-target-mode/contracts/`
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
