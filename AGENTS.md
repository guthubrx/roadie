<!-- SPECKIT START -->
Current SpecKit feature: `020-cef-web-hints`.

Contexte :
- `specs/020-cef-web-hints/spec.md`
- `specs/020-cef-web-hints/plan.md`
- `specs/020-cef-web-hints/research.md`
- `specs/020-cef-web-hints/data-model.md`
- `specs/020-cef-web-hints/contracts/`
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
