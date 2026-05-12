# Modèle de Données : Parking et restauration des stages d'écrans

## Entité : ÉcranLogique

Représente un écran reconnu par Roadie au-delà de l'identifiant instable fourni par macOS.

Champs :

- `logicalDisplayID` : identifiant Roadie stable, dérivé ou généré.
- `lastDisplayID` : dernier `DisplayID` macOS connu.
- `name` : nom exposé par macOS.
- `frame` : dernière frame complète connue.
- `visibleFrame` : dernière frame visible connue.
- `isMain` : dernier statut main connu.
- `index` : dernier index connu.
- `fingerprint` : empreinte calculée pour matcher un écran qui revient.
- `lastSeenAt` : date de dernière observation.

Règles :

- `lastDisplayID` peut changer sans créer automatiquement un nouvel écran logique.
- Deux écrans actifs ne peuvent pas partager le même `logicalDisplayID`.
- Une restauration automatique exige un match non ambigu entre l'écran revenu et une origine parkée.

## Entité : EmpreinteÉcran

Signature conservatrice utilisée pour reconnaître un écran revenu.

Champs :

- `nameKey` : nom normalisé.
- `sizeKey` : largeur/hauteur normalisées.
- `visibleSizeKey` : largeur/hauteur visibles normalisées.
- `positionKey` : position relative ou approximation de frame.
- `mainHint` : indicateur main/non-main.
- `previousDisplayID` : ancien display ID si disponible.

Règles :

- Le match strict `previousDisplayID` est préféré mais non obligatoire.
- Le match nom + taille + position est acceptable si un seul candidat existe.
- En cas d'égalité ou de doute, le résultat est ambigu et la restauration automatique est refusée.

## Entité : OrigineStage

Trace de l'emplacement d'une stage avant parking.

Champs :

- `logicalDisplayID` : écran logique d'origine.
- `displayID` : display ID d'origine au moment du parking.
- `desktopID` : desktop Roadie d'origine.
- `stageID` : stage ID d'origine.
- `position` : position d'affichage dans la liste des stages d'origine.
- `nameAtParking` : nom au moment du parking, pour diagnostic.
- `parkedAt` : date de parking.

Règles :

- L'origine ne doit pas être écrasée par les modifications faites pendant le parking.
- Le nom courant de la stage peut changer ; `nameAtParking` reste un indice historique.

## Entité : StagePersistée

Extension conceptuelle de `PersistentStage`.

Champs existants :

- `id`
- `name`
- `mode`
- `focusedWindowID`
- `previousFocusedWindowID`
- `members`
- `groups`

Nouveaux champs proposés :

- `parkingState` : `native`, `parked`, `restored`.
- `origin` : `OrigineStage?`.
- `hostDisplayID` : écran actif qui héberge la stage quand elle est parkée.
- `restoredAt` : date de restauration, si applicable.

Règles :

- Une stage `native` n'a pas d'origine de parking.
- Une stage `parked` DOIT avoir une origine et un écran hôte courant.
- Une stage `restored` peut conserver l'origine pour diagnostic, mais redevient gérée par son écran logique restauré.
- Les membres, groupes, focus et mode restent la source courante ; il n'y a pas de copie ancienne à restaurer.

## Entité : ScopePersisté

Extension conceptuelle de `PersistentStageScope`.

Champs existants :

- `displayID`
- `desktopID`
- `activeStageID`
- `stages`

Champs proposés :

- `logicalDisplayID` : écran logique auquel ce scope appartient.
- `isDisplayPresent` : état dérivé au moment du snapshot.
- `lastKnownDisplayFingerprint` : empreinte de l'écran associé.

Règles :

- Un scope peut rester présent dans le JSON même si son écran est absent.
- Les scopes absents ne doivent pas être traités comme corrompus.
- Les scopes hôtes peuvent contenir des stages natives et des stages parkées, mais elles doivent rester distinguables.

## Entité : SessionParking

Ensemble de stages rapatriées depuis un écran disparu.

Champs :

- `sessionID` : identifiant de session.
- `originLogicalDisplayID`
- `originDisplayID`
- `hostDisplayID`
- `startedAt`
- `restoredAt`
- `stageIDs`
- `status` : `active`, `restored`, `ambiguous`, `abandoned`.

Règles :

- Une session active ne doit pas être dupliquée pour le même écran absent.
- Une session restaurée ne doit plus déclencher de déplacements.
- Une session ambiguë conserve les stages visibles sur l'écran hôte.

## Transitions d'état

```text
native
  └─ écran origine absent + stage non vide -> parked

parked
  ├─ écran origine reconnu avec confiance -> restored
  ├─ écran origine non reconnu ou ambigu -> parked
  ├─ stage vidée par utilisateur -> parked_empty
  └─ stage supprimée explicitement -> supprimée

restored
  └─ prochain snapshot stable -> native ou restored historique selon besoin diagnostic
```

## Compatibilité

- Les fichiers `stages.json` existants sans `parkingState`, `origin` ou `logicalDisplayID` doivent être lus comme `native`.
- Les champs inconnus doivent rester optionnels pour éviter de casser les utilisateurs existants.
- La migration ne doit pas déplacer de fenêtres au chargement seul ; les déplacements se font uniquement lors d'une transition de topologie stabilisée.
