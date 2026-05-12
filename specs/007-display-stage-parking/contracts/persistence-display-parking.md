# Contrat de persistance : display parking

## Fichier concerné

`~/.roadies/stages.json`

## Compatibilité ascendante

Roadie DOIT lire les fichiers existants sans champs de parking. Les valeurs par défaut sont :

- `logicalDisplayID` absent : calculé ou initialisé depuis le `displayID` courant.
- `parkingState` absent : `native`.
- `origin` absent : aucune origine de parking.
- `hostDisplayID` absent : aucun écran hôte.

## Champs proposés sur scope

```json
{
  "displayID": "display-live-or-last-known",
  "desktopID": 1,
  "activeStageID": "1",
  "logicalDisplayID": "logical-lg-hdr-4k",
  "lastKnownDisplayFingerprint": {
    "nameKey": "lg hdr 4k",
    "sizeKey": "3840x2160",
    "visibleSizeKey": "3840x2077",
    "positionKey": "0,0",
    "mainHint": false,
    "previousDisplayID": "display-old"
  },
  "stages": []
}
```

## Champs proposés sur stage

```json
{
  "id": "4",
  "name": "Perso",
  "mode": "bsp",
  "parkingState": "parked",
  "origin": {
    "logicalDisplayID": "logical-lg-hdr-4k",
    "displayID": "display-old",
    "desktopID": 1,
    "stageID": "4",
    "position": 2,
    "nameAtParking": "Perso",
    "parkedAt": "2026-05-12T06:30:00Z"
  },
  "hostDisplayID": "display-built-in",
  "members": []
}
```

## États valides

- `native` : stage normale.
- `parked` : stage rapatriée depuis un écran absent.
- `restored` : stage revenue sur son écran d'origine reconnu.

## Invariants

- Une stage `parked` DOIT avoir `origin`.
- Une stage `native` NE DOIT PAS exiger `origin`.
- Une stage `parked` conserve ses membres et groupes courants.
- La restauration déplace l'objet stage courant, elle ne remplace pas par une copie ancienne.
- Les scopes d'écrans absents peuvent rester dans le fichier sans être considérés comme corrompus.

## Migration

Au premier chargement :

1. Lire l'ancien JSON sans erreur.
2. Initialiser les champs absents en mémoire.
3. Ne pas écrire une migration tant qu'aucune mutation réelle n'a lieu.
4. Ne jamais déplacer une fenêtre pendant la simple lecture du fichier.
