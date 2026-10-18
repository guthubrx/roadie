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
Dépôt Outlook corrigé : deux gestes complets et six cycles de maintien rejoués en test isolé.
Échec sans correctif, succès avec correctif. 1550 tests combinés réussis en mode séquentiel.
Sources de production installées inchangées, UUID vérifié. PID 34131, quatre contrôles santé OK.
Session 034 implémentée et installée : une fenêtre encore illisible sur un autre écran
ne fait plus réduire les voisines. Reprise automatique dès lecture AX valide, budget conservé.
1484 tests isolés et 1551 tests combinés réussis. Contrôle réel avec disponibilité retardée
3 secondes : voisines stables, placement sans échec, cadres restaurés après fermeture.
UUID 2B510D42-C812-384F-952E-59E17AA95A6C, PID 15020, quatre contrôles santé OK.
Session 036 implémentée et installée : présence CG ID/PID distincte du placement,
conservation des groupes et du rail pendant le plein écran natif. 1490 tests isolés et
1557 combinés réussis. Reproduction réelle avant/après à 22 s ; huit affectations conservées.
Outlook récupéré dans une stage séparée après perte antérieure à l’installation.
PID 53642, signature stable, quatre contrôles santé OK ; diaporama de preuves vérifié.
Session 037 implémentée et installée : inventaire transmis au tiler, attente AX sur
le même écran, observations par lot, feuilles XPC exclues et glisser partagé verrouillé.
Sept mécanismes corrigés de 035 intégrés. 1587 tests dans 183 suites réussis ;
278 empreintes Sources/Tests inchangées. UUID 795C9759-EE86-3D9C-B720-0BCB7430213F.
PID 62842, signature stable, quatre contrôles santé OK. Dépôts natifs et plein écran
35 s vérifiés sur l'écran interne. Stage 4 restaurée, tests temporaires retirés.
Limites et preuves : specs/037-fiabilite-placement/validation/livraison037.md.
Session 038 implémentée et installée : champ de saisie AppKit, édition macOS,
sélection des suggestions par Haut/Bas et clic, validation du choix par Retour.
127 tests ciblés et 1597 tests / 185 suites réussis. Parcours natifs vérifiés.
PID 96284, signature stable, quatre contrôles santé OK ; T3 conservé.
Preuves et limites : specs/038-saisie-native/validation/livraison038.md.
Session 040 implémentée et installée : watcher du statut d'enregistrement filtré,
rappel poursuivi sur les autres membres, fenêtres réduites restaurées avant focus,
arrêt AX après délai dépassé et échecs de masquage détaillés.
1 612 tests / 188 suites et 26 tests de scripts réussis. Revue traitée.
UUID EAC639A1-B54B-339F-98AD-950C4D5F0F3E, PID 46802, quatre contrôles santé OK.
Preuves visuelles indisponibles ; limites : specs/040-reactivite-rappel/validation/validation.md.
Session 041 implémentée et installée : aperçu translucide du réordonnancement à la
future place des cartes, trait bleu retiré, destinations fixes et aimantation réglable
0–100 % dans Paramètres > Rail (défaut 50). 1 616 tests / 189 suites réussis,
puis 22 tests ciblés après revue ; deux revues traitées. UUID
3533388F-83B1-3F5A-995C-B525D7656291, PID 83654, quatre contrôles santé OK.
Preuves visuelles incomplètes : bureau inaccessible. Validation :
specs/041-apercu-reordonnancement/validation/validation.md.
Current SpecKit feature: `041-apercu-reordonnancement`.

Contexte :
- `specs/041-apercu-reordonnancement/spec.md`
- `specs/041-apercu-reordonnancement/plan.md`
- `specs/041-apercu-reordonnancement/research.md`
- `specs/041-apercu-reordonnancement/tasks.md`
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
