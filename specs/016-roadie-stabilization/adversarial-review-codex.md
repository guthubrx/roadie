# Contre-revue adverse du plan : Codex

- **Date** : 2026-10-10
- **Agent interrogé** : Codex (fournisseur OpenAI), modèle GPT-6.1-Sol, raisonnement élevé, via délégation T3 (`bridget who` : aucun agent connecté)
- **Question** : correction et suffisance des décisions R1, R3, R5, R8, R9 ; découpage en lots parallèles ; trous de couverture ; minimalisme
- **Verdict reçu** : BLOCKED (points 1 à 7 à trancher avant l'implémentation parallèle)
- **Contexte** : les agents de la vague 1 venaient d'être lancés ; les corrections retenues leur ont été transmises par message pendant leur travail, avant tout commit de leur lot.

| # | Objection | Vérifiée comment | Retenue | Raison |
|---|---|---|---|---|
| 1 | `save` d'un état lu hors verrou perd des mises à jour ; fichiers sans propriétaire | lecture `WindowContextActions.swift:334`, `DesktopCommands.swift:147` | oui | fichiers attribués aux lots A et E, conversion à `mutate` |
| 2a | Deadlock si `mutate` rappelle `writeThrowing` | lecture `FileLock.swift:50-70` : nouveau `open` + `flock` par appel | oui | écriture « verrou déjà tenu » séparée |
| 2b | `mutate` doit être `throws` | analyse des appelants | non | signature `rethrows` déjà consommée par les autres lots ; erreurs d'I/O journalisées sans écriture |
| 3 | Le délai AX borne un appel, pas une commande | lecture `SystemSnapshotProvider.swift:717` (`set` en 3 écritures) | oui | abandon au premier échec, budget ~1 s |
| 4 | R5 vise `arguments`, absent de `LayoutIntent` | lecture `LayoutIntentStore.swift:4-47` | oui | `zoomedWindowID` typé |
| 5 | `events subscribe` bloquerait le fil principal du daemon | lecture `Sources/roadie/main.swift:983` (`while true`) | oui | liste explicite de commandes finies |
| 6 | Le repli local contredit l'écrivain unique | raisonnement sur le contrat | oui | repli seulement si verrou d'instance libre |
| 7 | Fenêtre de perte de 30 s entre snapshots de restauration | lecture `RestoreSafetyService.swift:131,156` | oui | union snapshot + membres persistés, récupération au démarrage |
| 8 | `lastSeenAt` empêche zéro écriture au repos | lecture des méthodes `StageStore` | oui | dates de présence non réécrites |
| 9 | Mémo de 90 ms inférieur à la période du focus-souris (100 ms) | lecture `FocusFollowsMouseController.swift:23` | oui | producteur unique, 150 ms, invalidation |
| 10a | R10 ne reconnaît pas une action utilisateur | raisonnement | oui | saisie utilisateur < 1 s requise |
| 10b | R11 autorise un rattachement au démarrage avec pid vivant | relecture R11 vs FR-006 | oui | exception supprimée |
| 11 | Interfaces et propriétaires manquants | relecture plan | oui | propriétaires ajoutés, contrat zoom fixé |
| 12a | Rotation des logs seulement au démarrage | lecture `scripts/start` | partiel | rotation au démarrage retenue ; borne pendant l'exécution notée comme limite connue (logs stdout réduits au minimum) |
| 12b | Moyen de quitter l'app DMG absent | relecture | non | hors périmètre (barre de menus exclue dans Assumptions) ; noté en limite |
| 13 | Déplacement intégral de la CLI = sur-ingénierie | relecture | partiel | déplacement conservé (évite deux chemins de dispatch), mais seules les commandes finies sont routées |

---

# Round 2 : contre-revue de l'implémentation

- **Date** : 2026-10-10
- **Agent interrogé** : Codex, GPT-6.1-Sol, raisonnement élevé (délégation T3)
- **Base relue** : commit `3df5c6f` (`git diff 3560183..HEAD -- Sources Tests`)
- **Verdict reçu** : BLOCKED (6 P1, 1 P2)
- **Bilan round 1** : objections 2a, 4, 5, 8, 10b corrigées ; 1, 3, 6, 7, 9, 10a partiellement ; 11 corrigée avec doc à aligner (fait : `dea2c68`, `d6b2f7e`).

| # | Objection | Vérifiée comment | Retenue | Tâche |
|---|---|---|---|---|
| 1 | Scopes préparés hors verrou puis recopiés dans `mutate` | lecture `WindowBookmarkCommands.swift:93`, `DesktopCommands.swift:291` ; `save` restants confirmés par Converge | oui | T202, T207 |
| 2 | Restauration limitée aux fenêtres du snapshot visible ; position cachée non reconnue si l'écran droit disparaît | lecture `RestoreSafetyService.swift:122`, `HiddenWindowPlacement.swift:35` | oui | T209 |
| 3 | Résultat `.clamped` encore caché validant un arrêt propre | lecture `RestoreSafetyService.swift` (seuls `applied`/`failed` comptés) | oui | T209 |
| 4 | Focus sur une voisine laisse le scope bloqué par le zoom | lecture `LayoutMaintainer.swift:229,1105` et test `:3587` | oui | T208 |
| 5 | Abonnements AX par fenêtre sans abandon ; erreurs intégrées non mises de côté | lecture `AXWindowEventObserver.swift:149-170` | oui | T210 |
| 6 | Commande CLI locale de lecture pouvant changer la stage active | lecture `FocusFollowsMouseController.swift:105` (`guard monitoring else { return true }`) | oui | T211 |
| 7 | Pas de producteur unique de snapshot par cycle | lecture `DaemonSnapshot.swift:164-178` | oui | T212 |
