# Contre-revue adverse : SPEC-017

## Round 1 : plan (2026-10-11)

- **Agent** : Codex, modèle GPT-6.1-Sol (fournisseur OpenAI), via `delegate_task` T3. `bridget who` ne liste aucun agent, comme lors de la 016.
- **Question** : le plan donne-t-il vraiment une passe unique ? Défauts de R6, R7, R1 et R10 ? Découpage en lots ? Ce qui manque pour égaler yabai ?
- **Verdict** : **BLOCKED** (6 objections bloquantes, 6 majeures).

| # | Objection | Vérifiée comment | Retenue | Suite |
|---|---|---|---|---|
| 1 | Les ticks de suite gardent le tâtonnement ; le tick quitte après chaque étape | lecture `LayoutMaintainer.swift:205-258` : 7 `return` anticipés | oui | A1 : plan de passe unifié, plus de tick de suite sur « acted », échos filtrés dans le callback |
| 2 | R4 contredit le budget d'écriture ; mauvais axe ; une réponse transitoire est prise pour un minimum | lecture R4, `spec.md` FR-005, `LayoutMaintainer.swift:505, 1415, 1565` | oui | A2 : budget par version, refus confirmé par deux observations, ancêtre de l'axe contraint, chevauchement accepté ; FR-005 reformulée |
| 3 | Le tâtonnement survit en `masterStack` et `bsp` | lecture `MasterStackLayoutStrategy.swift:76`, `BSPLayoutStrategy.swift:168` | oui | A3 : matrice par mode ; garantie « une passe » limitée aux modes à arbre et écrite dans la spec |
| 4 | R6 ne prouve pas un geste (clic ailleurs, auto-redimensionnement, BTT, CLI locale, ancien readBack) | lecture R6 et `yabai event_loop.c:1117-1228` | oui | A4 : session de geste par fenêtre, classe « changement externe » ramenée une fois à l'arbre, frame acceptée liée à la version |
| 5 | R7 peut fermer la garde trop tôt ; la notification est globale | lecture R7, `yabai window_manager.c:2258-2295` | oui | A5 : garde par écran, preuve par le type du bureau (lecture privée, ADR 010), repli public, `closedBy` distinct |
| 6 | 200 ms de calme contre l'objectif de 150 ms ; test de rafale insuffisant | lecture `LayoutMaintainerTests.swift:892-965` : une disparition puis +3 s, pas de rafale | oui | A6 : pas d'attente pour un changement isolé, stabilisation seulement en rafale, nouveaux tests |
| 7 | Le cache doit revalider après le verrou et lier signature et octets | lecture `JSONPersistence.swift:60-82` (relit bien après le verrou aujourd'hui) | oui | A7 : contrat fd + fstat, revalidation sous verrou, publication après succès |
| 8 | La migration perd sa provenance ; inférence dangereuse ; ordre des membres absent | lecture data-model et interface `inferred` | oui | A8 : cas d'enum conservé, migration explicite sous verrou avec sauvegarde des octets bruts et écriture forcée, repli ordonné |
| 9 | Grâce réelle de 30 min et non 45 s ; opérations sur l'arbre projeté non définies | lecture `DaemonSnapshot.swift:75` (30 min) | oui | A9 : grâce réelle, destruction confirmée, arbre projeté à identité de split conservée |
| 10 | Vagues non compilables ; `tick()` renvoie `MaintenanceTick` ; interface `applyTreeScope` manquante | lecture `LayoutMaintainer.swift:103`, `LayoutCommandService.swift:80` | oui | A10 : aucune suppression avant la vague 3, stubs compilables, L7 par étapes |
| 11 | Glisser (grâce 0,9 s), bascules et signets gardent des placements intermédiaires ; fichiers hors lots | lecture `WindowDragActivity.swift:27`, `StageCommands.swift:1029-1041` | oui | A11 : `WindowDragActivity` confié à L6 ; `DesktopCommands` et `WindowBookmarkCommands` confiés à L9 ; frames finales directes |
| 12 | Mesure : identité des événements, republication, épisodes coupés, coûts AX non mesurés | lecture `DaemonSnapshot.swift:1890-1900` (plafond 0,6 s), `AXWindowEventObserver.swift:16` | oui, en partie | A12 retenu. Limite assumée : les lecteurs du snapshot gardent leur cadence actuelle (rescan au plus toutes les 150 ms), coût préexistant hors périmètre |

Aucune objection rejetée. L'objection 12 est retenue en partie, avec une limite écrite.

## Round 2 : plan amendé (2026-10-11)

- **Agent** : Codex GPT-6.1-Sol (OpenAI), via `delegate_task`.
- **Verdict** : **BLOCKED** (2 bloquantes, 8 majeures).
  - Objections du round 1 **levées** : O1, O3, O7, O8, O11.
  - Objections **partielles** : O2, O4, O5, O6, O9, O10, O12.

| # | Objection | Vérifiée comment | Retenue | Suite |
|---|---|---|---|---|
| 1 | La version renouvelle le budget à chaque correction ; la visibilité n'est pas couverte ; compteurs par scope | lecture A2, data-model | oui | A13 : génération globale ouverte par une intention externe, budget partagé par tous les chemins |
| 2 | L'écho absorbé supprime la confirmation du refus | lecture A2, A4, T033 | oui | A14 : confirmation marquée avant absorption, relecture fraîche à échéance (transmis à L3 en cours) |
| 3 | Le plan dédoublonné n'assure pas un état final cohérent | lecture A1, exemple règle puis masquage | oui | A15 : état logique, puis calcul, puis arbitrage, puis application, sur une copie de travail |
| 4 | Faisabilité après les bornes et marges réelles | lecture data-model (bornes 0,05-0,95) | oui | A16 (transmis à L4 en cours) |
| 5 | Session de geste : clic sans cible, double traitement du relâchement, moniteur local | lecture A4, doc Apple des moniteurs globaux | oui | A17 |
| 6 | Le premier placement d'une rafale ne peut pas être évité | raisonnement temporel 0 / 15 / 80 ms | oui | A18 : premier placement conservé, 2 passes au plus en rafale, test adapté |
| 7 | Contrat de preuve de la sonde privée | lecture `yabai space.c:88`, `display.c:225` | oui | A19 (transmis à L3 en cours) |
| 8 | Stubs incomplets : constantes, gestes, protocole d'écriture | lecture plan, T053 | oui | A20 (génération via le protocole `WindowFrameWriting`, transmis à L3) |
| 9 | L'identité des splits projetés n'est pas transportée | lecture interface `projected` | oui | A20 : opérations directes sur l'arbre complet avec exclusions (transmis à L4) |
| 10 | Stabilité observée non mesurable ; épisode fermé pendant une garde | lecture contrat, A12 | oui | A20 : événement `layout_stable`, épisode ouvert tant qu'une échéance est en attente |

Aucune objection rejetée. Pas de round 3 sur le plan : les points restants sont des précisions de contrat, appliquées. La contre-revue de l'implémentation vérifiera leur réalisation.
