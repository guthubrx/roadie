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
Session 030 implémentée et installée : récupération des fenêtres sur écran absent au démarrage.
1471 tests isolés et 1527 tests combinés réussis. Redémarrage vérifié, quatre contrôles santé OK.
Session 031 implémentée et installée : numéro et nom temporaires ; Alt gauche grille, Alt droite libellés.
1 540 tests combinés réussis, captures avant/après et expiration vérifiées, santé OK.
Les repères des stages vides suivent aussi la visibilité temporaire des noms.
Session 032 implémentée et installée : avant des vignettes aligné, hauteur des emplacements réglable,
repère de dépôt et géométrie stable pendant le glisser. Hauteur installée 120 points, gap 13 conservé.
1477 tests isolés et 1544 tests combinés réussis. Deux rails vérifiés, dix scopes conservés.
Session 033 implémentée et installée : légendes compactes sous les aperçus, perspective optionnelle.
14 points, écart 4, emplacement 112 points ; visibilité temporaire et raccourcis conservés.
Dépôt Outlook corrigé et reproduit par test ; glisser physique non rejoué après changement de groupe.
1482 tests isolés et 1549 tests combinés réussis en mode séquentiel. PID 34131, santé OK.
Current SpecKit feature: `033-legendes-compactes`.

Contexte :
- `specs/033-legendes-compactes/spec.md`
- `specs/033-legendes-compactes/plan.md`
- `specs/033-legendes-compactes/implementation.md`
- `specs/033-legendes-compactes/tasks.md`
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
