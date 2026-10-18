# Validation - 047 Fenêtre flottante

Date : 18 octobre 2026. Branche : session-047-fenetre-flottante, base cad1b466.

## Implémentation

- `WindowPinScope.stage` : épinglage visible seulement dans sa stage d'origine
  (`Sources/RoadieDaemon/StageStore.swift`).
- `WindowContextActions.toggleFloating(windowID:)` et action `floatStage`
  (`Sources/RoadieDaemon/WindowContextActions.swift`).
- `roadie toggle floating` implémentée et routée vers le daemon
  (`Sources/RoadieDaemon/CLICommandRouter.swift`).
- Menu « Fenêtre » : « Flotter dans cette stage », « Revenir au tuilage »
  (`Sources/RoadieDaemon/TitlebarContextMenuController.swift`).
- Accesseur `SnapshotService.effectiveEvents`, sur le modèle des accesseurs existants.

## Tests

- Rouge avant code : compilation des 6 premiers tests en échec (types et méthode absents).
- Tests 047 : 11 tests, tous verts. Mutation : rendre `.stage` visible partout fait
  échouer 3 tests ; code d'origine restauré.
- Suite complète finale : 1 707 tests / 200 suites, verts en 12,594 s.
- Instabilité préexistante constatée : `daemonListeningOnSocketIsUsedEvenWithoutPidFile`
  et `distributedSignalFromChildProcessAppliesLayoutAndStageNamesOnce` échouent aussi
  sans la suite 047 (2 exécutions sur 3). Avec la suite 047 sans isolation
  `@MainActor`, 3 exécutions sur 3 vertes. Aucune modification de ces tests.
- Première version de la suite 047 isolée sur le fil principal : elle retardait le
  test de socket au-delà de 5 s. Isolation retirée, inutile pour ces API.

## Revue indépendante

Bridget a choisi Claude Haiku 5.5 (même fournisseur, pas d'autre fournisseur proposé).
Verdict : APPROVE_WITH_CHANGES. Traitement :

| Objection | Vérifiée comment | Retenue | Suite |
|---|---|---|---|
| Ancienne version : `pinScope = "stage"` rend tout `stages.json` illisible | Lecture du décodage synthétisé et de `loadFailure` | Oui | Format compatible : `desktop` + `floatingInStage`, test de lecteur ancien |
| Pas de test du masquage au changement de stage | Lecture des tests | Oui | Tests masquage et restauration par `LayoutMaintainer` |
| Pas de test du retour au tuilage pour les voisines | Lecture des tests | Partiel | Test : le tuileur place la voisine, jamais la fenêtre flottante |
| Pas de test de relecture du fichier | Lecture des tests | Oui | Test de rechargement de `StageStore` |
| Pas de test CLI positif | Lecture des tests | Oui | Tests de routage `toggle floating` |
| Cas `.stage` de `visibility(in:)` répète le retour du garde | Lecture | Non | Style du fichier conservé, cas explicite plus lisible |

## Essai réel

Release installée et redémarrée : UUID 7DE5FFC6-67B3-3CD2-A7B3-3C4CB9A1694E,
PID 64518, signature `roadied-cert` conservée, quatre contrôles santé OK.

Le premier essai a révélé un défaut : la commande s'exécutait dans le terminal,
sans Accessibilité, et répondait « no managed window ». Correction : routage vers
le daemon, test ajouté, réinstallation.

Second essai sur la fenêtre active Firefox 54169 :
- premier appel : « pin cette stage (flottante) », `stages.json` contient
  `pinScope = desktop` et `floatingInStage = true`, `query state` publie `isFloating = true` ;
- second appel : « pin removed », épinglage retiré, `isFloating = false`.

Non vérifié en réel : masquage au changement de stage (couvert par les tests),
rendu du menu de barre de titre. Fonctionnalité nouvelle, pas une correction :
aucun diaporama de preuves requis.
