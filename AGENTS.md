## Nettoyage obligatoire après livraison

Demande utilisateur du 31 octobre 2026 : ne pas clôturer par le seul commit, la fusion et le push. Après vérification du code actif et du commit distant, supprimer les branches intégrées, worktrees libérés, caches et binaires temporaires devenus inutiles dans le périmètre du travail. Vérifier leur provenance, leur intégration et leur absence d'utilisation avant suppression. Conserver le worktree d'un fil actif, les changements non intégrés, les preuves originales, les exécutables installés et le retour arrière utile ; expliquer ces exceptions dans le bilan. Toute modification publiable du périmètre doit être commitée et poussée ; ne pas ajouter les données privées, preuves brutes ou caches dans Git.

## Journal des sessions

Le bilan de chaque session livrée est dans `.specify/memory/sessions/journal.md`.
Ajoute le bilan d'une nouvelle session à la fin de ce fichier, pas ici.

## Tests

- Suite complète : `./scripts/test --no-parallel` (environ 80 secondes). Sans `--no-parallel`,
  des tests sensibles au temps échouent quand la machine est chargée.
- Un groupe de tests : `./scripts/test --no-parallel --filter NomDeLaSuite`.
- Tests des scripts : `python3 -I -B -m unittest discover -s scripts/tests`.
- Un test hors de ton périmètre échoue une fois : relance-le seul. S'il échoue deux fois de
  suite, arrête et signale-le avec la commande et le message.
- Ajouter un réglage : suivre `docs/dev/ajouter-un-reglage.md`.

## Pièges connus

- **Signature** : `make install` signe avec le certificat `roadied-cert`. Une autre signature
  fait perdre la permission Accessibilité.
- **Build de test périmé** : après l'ajout d'un champ à une structure de `RoadieCore`, les
  tests peuvent planter au signal 11 (« outlined destroy »). Remède : supprimer
  `.build/arm64-apple-macosx/debug/RoadieTilerTests.build`, puis relancer les tests.
- **Symbole introuvable à l'édition de liens** (« Undefined symbols … TargetModeConfig.init ») :
  `touch Sources/RoadieDaemon/OverviewController.swift`, puis relancer.
- **Processus enfants** : `roadied` ignore SIGTERM et un enfant en hérite. Rétablir les
  signaux par défaut au lancement de l'enfant.
- **Audit V15** : le lancer sur un checkout hors de `.worktrees`.
- **Avertissement sans gravité** : `scripts/test` utilise un dossier personnel temporaire ;
  SwiftPM affiche « failed loading cached manifest … Not a directory ». Ce n'est pas une erreur.
- **Commits** : nommer les fichiers (`git add -- <fichiers>`), jamais `git commit -a`.

<!-- SPECKIT START -->
Current SpecKit feature: `155-consolidation-projet`.

Contexte :
- `specs/155-consolidation-projet/spec.md`
- `specs/155-consolidation-projet/plan.md`
- `specs/155-consolidation-projet/tasks.md`
<!-- SPECKIT END -->

## Revues indépendantes

Autorisation permanente donnée le 21 octobre 2026 : lancer les revues indépendantes
sans nouvelle demande de confirmation. Le responsable traite leurs constats et
poursuit les tests et la livraison autorisés.

<!-- SPECKIT-USER START -->
# Couche utilisateur SpecKit

- Source de verite utilisateur: `~/.speckit/`.
- Avant une feature/refactor structurel: executer ou appliquer `/speckit.sync`.
- Charger `.specify/memory/constitution.md` pour les gates projet.
- Charger `.specify/memory/standards.md` pour retrouver les refs et baselines research.
- Ne pas modifier directement `.agents/skills/speckit-*`, `.specify/templates/*`, `.specify/scripts/*` ou `.specify/workflows/*`.
- Les commandes utilisateur canoniques vivent dans `~/.speckit/commands/` et sont publiees vers Codex/Claude/Gemini par `~/.speckit/scripts/sync-agent-adapters.py`.
<!-- SPECKIT-USER END -->
