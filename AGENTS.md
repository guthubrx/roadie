<!-- SPECKIT START -->
Current SpecKit feature: `022-audit-remediation`.

Contexte :
- `specs/022-audit-remediation/spec.md`
- `specs/022-audit-remediation/plan.md`
- `specs/022-audit-remediation/research.md`
- `specs/022-audit-remediation/data-model.md`
- `specs/022-audit-remediation/contracts/`
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
