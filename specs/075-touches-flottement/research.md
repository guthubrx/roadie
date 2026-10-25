# Recherche 075

## R1 Lecture des modificateurs dans la barre
`SearchInputPanel.sendEvent` reçoit tous les événements du panneau non activant. Les touches
tenues arrivent en `.flagsChanged` : il suffit de les transmettre (`onFlags`). Retour arrive en
`.keyDown` keyCode 36/76 avec `modifierFlags` : `.confirm` porte déjà Maj et Commande ; Option et
Contrôle y sont ajoutés. Décision : ajouter `option` et `control` à `SearchKeyInput.Kind.confirm`
plutôt qu'un champ parallèle (un seul endroit dit ce que Retour a reçu). 18 usages à adapter.

## R2 ⌘ + chiffre
`performKeyEquivalent` intercepte ⌘ + lettre pour l'édition. Les chiffres 1 à 9 y sont ajoutés et
deviennent `.pick(n)`. Sans liste riche (mode commande), `.pick` est ignoré.

## R3 Raccourci des verbes
`TargetSearchHotkey` enregistre un raccourci Carbon avec signature et type d'événement
paramétrables ; la vue d'ensemble l'utilise déjà (`OverviewController`). Une seconde instance
avec `actions_hotkey` (défaut `cmd+ctrl+opt+shift+f`, Capslock = Hyper chez l'utilisateur) suffit.
La commande CLI passe par `queueTargetModeRuntimeCommand` comme `target search`.

## R4 Une seule règle par application
`WindowRuleEngine.evaluate` applique l'action de la première règle correspondante ;
`DaemonSnapshot` aussi (`firstMatch`). Deux règles distinctes « affinity » et « flottement » pour
la même application s'annuleraient. Décision : le flottement (`floating = true`) ou le tuilage
(`manage = true`) est porté par la règle `affinity-app-<bundle>`. Sauvegarder l'affinité conserve
`floating`/`manage` ; retirer l'affinité garde la règle si un choix de tuilage reste, et
inversement.

## R5 Adresse de recherche web
Aucune configuration web existante. Clé `experimental.target_mode.web_search_url`, défaut
`https://www.google.com/search?q={query}`, `{query}` encodé (`addingPercentEncoding`,
`.urlQueryAllowed` sans `&+=`). Reprise par la session 077 pour le repli.
