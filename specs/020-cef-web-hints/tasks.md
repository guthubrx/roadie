# Tasks: Lettres d'accès dans Bluejay

**Input**: `specs/020-cef-web-hints/` (spec, plan, research, data-model, contracts, reuse-audit)
**Tests**: oui pour les fonctions pures ; mesure `targets.app_scan` et test manuel pour le parcours AX réel.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: User Story 1 - Bluejay publie son contenu (Priority: P1)

- [x] T001 [US1] Créer la branche `pr/029-macos-renderer-accessibility` depuis `origin/master` dans un worktree dédié du dépôt `/Users/moi/11.Repositories/grayjay`, et ajouter `--force-renderer-accessibility` au démarrage CEF sur macOS uniquement dans `Grayjay.Desktop.CEF/Program.cs:394`. Résultat observable : diff d'une ligne, Windows et Linux inchangés.

---

## Phase 2: User Story 2 - Lettres sur les éléments cliquables sans sémantique (Priority: P1)

- [x] T002 [US2] Écrire les tests de `AppTargetQueryService.keepsFocusableLeaf(path:nextFocusablePath:)` (pas de suivant, suivant descendant, suivant frère au préfixe trompeur `0.1` / `0.10`, suivant non descendant) dans `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`.
- [x] T003 [US2] Implémenter `keepsFocusableLeaf` dans `Sources/RoadieDaemon/AppTargetQueryService.swift`. Résultat observable : T002 passe.
- [x] T004 [US2] Dans `LiveAppTargetProvider.scan` : suivre l'appartenance à une zone web le long de la pile ; pour un élément de zone web non candidat, hors `AXWebArea`, de profondeur < `max_depth`, lire `AXFocused` modifiable ; tenir en préordre les marqueurs (focalisables de zone web, sous-arbres inconnus à `max_depth` ou illisibles) ; rien sous une cible de zone web déjà retenue ; à la fin, ajouter après les cibles historiques les feuilles retenues par `focusableLeaves` (pure, testée), avec le marqueur `isFocusableLeaf` accepté par `targets(from:)`. Corrigé après contre-revue BLOCKED. Résultat observable : build OK ; comportement vérifié en T009.

---

## Phase 3: User Story 3 - Tri mesurable (Priority: P2)

- [x] T005 [US3] Écrire les tests de `AppTargetQueryService.rejectedRoleSummary(_:limit:)` (tri décroissant puis alphabétique, limite 5, vide) dans `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`, et adapter le test d'événement de `Tests/RoadieDaemonTests/TargetHintServiceTests.swift` aux champs `focusableAdded` et `rejectedRoles`.
- [x] T006 [US3] Implémenter `rejectedRoleSummary`, ajouter `focusableAdded` et `rejectedRoles` à `AppTargetScanStats` et à `eventDetails`, les remplir dans `scan`, dans `Sources/RoadieDaemon/AppTargetQueryService.swift`. Résultat observable : T005 passe.

---

## Phase 4: Polish & vérification

- [x] T007 [P] Documenter la règle « feuille focalisable », le cas CEF (`--force-renderer-accessibility`) et les champs ajoutés dans `docs/fr/features.md` et `docs/en/features.md`.
- [x] T008 Lancer `./scripts/test` (suite complète) et `./scripts/with-xcode swift build`. Résultat observable : 0 échec.
- [x] T009 Installer Roadie (`make install`, `make restart`), lancer Bluejay avec l'option (`open -a /Applications/BlueJay.app --args --force-renderer-accessibility`, en attendant la build T010), mesurer Bluejay, Finder et T3 Code ; consigner dans `specs/020-cef-web-hints/implementation.md`. Résultat observable : Bluejay `candidates` ≥ 20 et `focusableAdded` > 0 (SC-001), Finder 58 et T3 Code 150 (± 5 %, SC-003), aucune cible en double (SC-004). Validation utilisateur : une lettre de la barre latérale ouvre la page (SC-002).
- [x] T010 Intégrer `pr/029-macos-renderer-accessibility` dans `bluejay/all-features` (restaurer le worktree d'intégration absent), construire avec `build-bluejay-with-prs.sh`, vérifier selon `AGENTS.md` du dépôt Grayjay. Résultat observable : `BlueJay.app` lancé depuis le Dock passe l'option à `dotcefnative` (`ps`), et `sawWebArea=true` sans argument manuel.

## Dependencies & Execution Order

- T001 et T010 : dépôt Grayjay, indépendants de Roadie jusqu'à T010.
- T002 → T003 → T004 ; T005 → T006 (après T004, même fichier) ; T007 indépendante.
- T008 après T002-T007 ; T009 après T008 ; T010 après T001 et T009.

## Convergence

- [x] T011 [US2] Écart code/artefacts (passage 1) : deux changements faits pendant T009 sur mesure, absents des tâches. (a) Règle anti-doublon : une cible retenue qui enveloppe une seule feuille garde sa lettre, la feuille est écartée ; un conteneur garde toutes ses feuilles (`leavesKeptUnderCandidates`, testée) ; remplace le blocage sous toute cible retenue, qui écartait les 12 feuilles de Bluejay sous un `AXGroup` géant doté d'`AXPress`. (b) Pas d'attributs boost dans les zones web (`AXChildren` seul) : Bluejay 62-73 → 1 516-1 544 éléments lus en 250 ms, T3 Code 124-136 → 58 ms à cibles égales. Consigner dans `research.md`, `data-model.md` et `implementation.md`.
- [x] T012 [US2] Écarts (passage 2, après retour utilisateur « pas de lettres sur les vidéos », page Abonnements) corrigés sur relevés jetables sans texte : (a) dédoublonnage du parcours par `CFHash` seul : 12 éléments distincts écartés (`CFEqual=false`), dont toute la zone de contenu `0.0.0.1`-`0.0.0.4` → `CFIdentitySet` (hash + `CFEqual`), testé, défaut antérieur à 018 ; (b) ~1 000 abonnements défilés réduits à 1 point épuisaient le budget → pas de descente sous 4 points (`isHintable`, même seuil que l'affichage), marqueur « inconnu » seulement si caché (≤ 1 point ou hors fenêtre, `hidesContent`) : la barre de progression de 4 points des cartes ne disqualifie plus la carte ; (c) anti-doublon par comptage rejeté par la contre-revue round 4 → `duplicatesTarget` (feuille couvrant ≥ 80 % de la cible retenue qui l'enveloppe) ; (d) feuilles ajoutées dans la limite `max_targets` (audit OBS-001). Résultat : Bluejay Abonnements 80 cibles dont 73 feuilles ; validation utilisateur (lettres sur les vidéos, ouverture, aucun doublon).
