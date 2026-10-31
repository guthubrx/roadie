# Tâches — Session 144

Statut : Implemented — pipeline livré. Exécution séquentielle ; aucun parallélisme de fichiers.

## Cadrage et fondations
- [x] T001 Conserver le cadrage, résoudre le prototype de propriété souris et écrire les artefacts de conception dans specs/144-effets-reglables/. Vérifié : frame AX 450×800, reflow visible, mouvements et mouseUp neutralisés ; limites conservées.
- [x] T002 Auditer chaque responsabilité du plan dans specs/144-effets-reglables/reuse-audit.md et demander la contre-revue du plan. Vérifié : PASS, neuf items ; admission distante refusée et tracée.
- [x] T003 Exécuter Analyze sur spec/plan/tasks, corriger les écarts non ambigus et relire une fois ; consigner dans specs/144-effets-reglables/analysis.md. Résultat : chaque FR/SC couvert, aucun CRITICAL persistant.
- [x] T004 Écrire docs/decisions/024-effets-et-propriete-glisser.md après recherche de numéro libre. Résultat : propriété, contrat différé et limites macOS compréhensibles sans contexte du fil.

## US1 — Réglages et mouvement commun
- [x] T005 Ajouter les tests de configuration et du calcul pur dans Tests/RoadieDaemonTests/Spec144EffectsTests.swift. Vérifier défauts, héritage, bornes, final exact, courbes, ressort et vitesse conservée.
- [x] T006 Étendre Sources/RoadieCore/Config.swift et ajouter le calcul de mouvement Sources/RoadieCore/Motion.swift après recherche d’existant. Résultat : tests T005 réussis, aucun avertissement de table animations ignorée.
- [x] T007 Ajouter la catégorie et les descripteurs FR/EN dans Sources/RoadieDaemon/SettingsCatalog.swift, SettingsCatalogEffects.swift et SettingsOrganization.swift ; valider TOML et édition. Résultat : catalogue complet, aucun effet de géométrie lors de modification.
- [x] T008 Ajouter l’ordonnanceur de transitions Sources/RoadieDaemon/EffectAnimator.swift, dernière cible, vitesse, interruption et activation indépendante de macOS. Tests : timer absent au repos et après terminaison, aucune ancienne fin rejouée.
- [x] T009 Remplacer les transitions locales dans Sources/RoadieDaemon/RailPanel.swift et OverviewPanel.swift. Résultat : même moteur et profils, ancien animation_ms compatible, aucun cubic/150ms propre à overview.
- [x] T010 Raccorder les apparitions/disparitions de lanceur, sélecteur et overview dans TargetOverlayPresenter.swift, WindowSwitcherPanel.swift et OverviewPanel.swift. Résultat : clavier restitué immédiatement, nouvelle présentation pendant fondu correcte, interrupteurs par action actifs.
- [x] T011 Ajouter l’aperçu local de la page Effets dans les vues de paramètres existantes. Résultat : chaque profil/courbe produit une démonstration sans déplacer une application ; FR/EN lisibles.

## US2 — Vraie destination
- [x] T012 Étendre les doubles et tests de session dans Tests/RoadieDaemonTests/Spec144RealDropTests.swift. Résultat : quatre combinaisons source/voisines, origine, dernière cible et refus couverts avant code du runtime.
- [x] T013 Étendre Sources/RoadieDaemon/LiveDropPreview.swift et DropPreviewController.swift pour la source possédée, commande seulement au changement de cible, retrait du contour et restauration. Résultat : T012 passe ; visée figée et aucune mutation du store pendant geste.
- [x] T014 Ajouter la qualification sémantique hors callback et capture souris dans le propriétaire WindowDragReorderController ; raccorder RailController.swift et UserInputActivity. Résultat : clic, double clic, contrôles/tabs et contenu préservés ; premier mouvement non qualifié garde le natif ; tap absent = contour explicite.
- [x] T015 Vérifier la prise en charge réelle depuis le titre et le rail, portrait/paysage, cible au déplacement suivant et dépôt sans dernier saut. Résultat : observations CG ID/PID et frames stables, capture du reflow réel ; test AppKit puis navigateur/éditeur/Finder selon T023.

## US3 — Interruptions et fenêtres animées
- [x] T016 Ajouter les tests du résultat différé et des fins dans Tests/RoadieDaemonTests/Spec144FrameTransitionTests.swift. Résultat : slowAX, génération externe, annulation/clic, refus et final sans faux succès couverts.
- [x] T017 Ajouter Sources/RoadieDaemon/FrameTransitionRuntime.swift en réutilisant InteractiveFrameDispatcher ; adapter Sources/RoadieDaemon/DaemonSnapshot.swift. Résultat : AX hors main, dernier lot/PID, cadence ≤30Hz, maintien borné et contrôle final réel.
- [x] T018 Adapter les consommateurs dans LayoutMaintainer.swift, LayoutCommandService.swift et StageCommands.swift ; relier l’arrêt et le maintien dans Sources/roadied/main.swift. Résultat : deferred ne crée ni refus ni réparation et changed reste exact ; stage/move utilisent leur politique, aucun chemin interactif 142/143 concurrencé.
- [x] T019 Ajouter et exécuter les tests Échap, nouveau geste, changement de stage/écran, fermeture, refus durable, pin, plein écran et configuration pendant effet. Résultat : aucune cible ancienne appliquée, source restaurée sans persistance et aucune ressource survivante.

## US4 — Mesures, convergence et livraison
- [x] T020 Exécuter scripts/test --filter Spec144 puis scripts/test et les tests scripts. Résultat : sorties/code retour enregistrés ; corriger les échecs avant suite.
- [x] T021 Exécuter Converge sur le code réel et chaque FR/SC après implémentation. Résultat : CONVERGED sans modifier tasks, ou ajouter seulement les tâches manquantes et les traiter, trois passages max.
- [x] T022 Demander la contre-revue adverse du code complet et traiter les objections vérifiées. Résultat : verdict et preuves, ou indisponibilité précise sans contournement.
- [x] T023 Rejouer la matrice native Finder/navigateur/éditeur/taille imposée, titre/rail, deux écrans, contenu statique/vidéo, annulation et réglages ; mesurer off/on Roadie+WindowServer+app (CPU/RSS/latence, GPU si outil accessible). Résultat : mesures brutes et limites dans specs/144-effets-reglables/validation.md ; aucune estimation inventée.
- [x] T024 Produire et vérifier preuves-corrections/2026-10-31-144-effets/preuves.html selon compétence ; conserver originaux hors Git. Résultat : étapes/cliqués réellement observés, images vérifiées, limites visibles.
- [x] T025 Exécuter l’audit V15 du code final et lire grade.json. Résultat : decision pass et release_blocked=false ; sinon livraison bloquée nommée.
- [x] T026 Figer le manifeste, vérifier gates puis committer/intégrer les socles 142/143 et la feature144 sur la cible autorisée. Résultat : SHA, ascendance, tests d’intégration et travail préexistant préservés.
- [x] T027 Pousser sans force et comparer git ls-remote à la cible locale. Construire/signer/installer avec procédure existante, activer et vérifier le code chargé (UUID/PID) et santé 5/5. Résultat : Git, disque et runtime prouvés distinctement ; aucune release implicite.
- [x] T028 Nettoyer uniquement les ressources éligibles du scope après sauvegarde des preuves ; conserver le worktree attaché si nécessaire. Compléter reçu et état SpecKit. Résultat : ressources retirées/conservées et raisons, aucun fichier préexistant perdu.

## Convergence
- [x] T029 Passage 1 : arrêter la transition AX dès un nouveau clic, avant la qualification du prochain geste. Écart FR-005/US3 : FrameTransitionRuntime.pulse valide la génération, mais aucun branchement mouseDown ne révoque son permis. Réutiliser UserInputActivity.observeGestures avec un callback de pression, le relier dans main.swift et tester le clic pendant une transition. Résultat : aucune ancienne cible après clic, sans consommation de takeGesture.
- [x] T030 Écart natif FR-003/SC-003 : entre les deux écrans à Spaces séparés, la frame réelle est écrite mais WindowServer masque le contenu pendant l’appui (capture de région : fond d’écran). Garder la source à son origine et le contour sur une autre destination d’écran. Restaurer aussi la source en quittant un candidat réel local. Documenter cette limite précise, tester et rejouer le cas réel avant livraison.
- [x] T031 Relecture des interruptions : les notifications d’écran, de Space et de veille n’incrémentent la génération qu’à la prochaine passe, qui peut être retenue par l’animation. Annulation du runtime raccordée aux trois observateurs existants avant leur attente. Preuve : branchements main.swift et tests du permis révoqué ; veille/changement physique d’écran non déclenchés sur le poste utilisateur.
- [x] T032 Relecture de la politique : appliquer les valeurs du groupe Apparition/disparition aux fondus, avec les surcharges du lanceur/sélecteur/overview prioritaires. Avant correction, seul son interrupteur commun était lu. Tester l’héritage, les priorités et l’indépendance des déplacements.
- [x] T033 Audit final : terminer les effets actifs dès modification de la politique, via le contrôleur de paramètres existant. Vérifier qu’une coupure rejoint les cibles exactes, libère le timer et ne retuile pas. Adapter le test natif de fermeture de l’overview à la fin bornée du fondu et vérifier la restitution immédiate du clavier. Conserver l’échec initial puis relancer la suite.
- [x] T034 Essai utilisateur : contour vert encore présent avec drop_preview=real sur le même écran. Relever la qualification et la décision du propriétaire du geste, sans I/O dans le callback, reproduire sur l’application concernée et corriger la cause. Préserver les profils et courbes choisis par l’utilisateur pendant la validation.
- [x] T035 Isoler la frontière matérielle dans les tests du runtime : lecture native des boutons conservée par défaut en production, état injecté dans les tests. Cause observée : nil de schedule pendant les glissers de l’utilisateur, malgré génération et politique correctes. Tester aussi le refus d’animation pendant un bouton enfoncé.

Clôture technique T034 : causes observées puis corrigées ; huit glissers Chrome natifs réussis avec annulation. Stabilité Firefox confirmée par l’utilisateur après chargement, y compris bas du titre et glisser rapide. Repli entre écrans également observé et expliqué. Converge final : troisième passage, aucune tâche ajoutée.
