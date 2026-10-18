# Plan - 047 Fenêtre flottante

Réutiliser l'épinglage de fenêtre (`PersistentWindowPin`), déjà :
- exclu de l'arbre (`DaemonSnapshot.swift`, adhésion seulement si `pin == nil`) ;
- persistant dans `stages.json`, nettoyé après 45 s d'absence ;
- masqué ou restauré à `lastFrame` selon `PersistentWindowPin.visibility(in:)` ;
- suivi lors des déplacements de stage (`updatePinHomeScope`) ;
- publié comme flottant (`ruleFloatingState`, `AutomationSnapshot.isFloating`).

Changements :
1. `WindowPinScope.stage` (valeur `stage`) : visible seulement si la stage
   active est la stage d'origine. Le premier test de `visibility(in:)` couvre déjà
   ce cas ; la nouvelle branche renvoie `outOfScope`.
2. `WindowContextActions.toggleFloating(windowID:)` : retire l'épinglage existant,
   sinon pose un épinglage `.stage`. Nouveau type d'action `.floatStage`.
3. CLI : `toggle floating` cible la fenêtre active et appelle (2).
4. Menu de barre de titre : entrée « Flotter dans cette stage » et libellé d'état.
5. Docs FR/EN, CHANGELOG, test d'aide CLI.

Aucun nouveau fichier source, type persistant ou dépendance.

Compatibilité (revue 1) : une valeur d'énumération inconnue ferait rejeter tout
`stages.json` par une version antérieure (état vide, écritures bloquées). La
portée `stage` s'écrit donc `pinScope = "desktop"` plus `floatingInStage = true`.
Une version antérieure ignore la clé et lit un pin de desktop. Codage explicite
de `PersistentWindowPin`, mêmes clés qu'avant.

Complexité : toggle O(n) sur les fenêtres du snapshot et les épinglages ;
visibilité O(1).
