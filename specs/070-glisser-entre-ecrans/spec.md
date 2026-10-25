# Session 070 - Glisser bureaux, stages et fenêtres d'un écran à l'autre

Demande du 25 octobre 2026 après le branchement d'un second écran. Choix validés : stage
à la place visée sur l'autre écran ; bureau entier devenant un bureau de l'autre écran,
inséré à la place visée, les deux écrans renumérotés ; fenêtre seule vers une stage d'un
autre écran.

## Comportement
- Les fenêtres arrivent masquées au coin de l'écran d'arrivée ; leurs cadres de retour
  sont recentrés dans sa zone utile (`CrossDisplayRelocation.swift`).
- Bureau affiché qui part : l'écran d'origine bascule d'abord sur un autre bureau.
- Écran tout juste branché : son bureau affiché compte comme occupé et glisse d'un cran.
- Stage déplacée : arrive inactive ; bureaux affichés inchangés.
