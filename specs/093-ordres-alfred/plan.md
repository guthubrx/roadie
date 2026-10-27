# Plan 093 - Ordres à Alfred traduits par Roadie

## Approche (research R1 à R6)
1. **Traduction pure** `AlfredBridge` (nouveau, `Sources/RoadieDaemon/AlfredBridge.swift`) :
   `translate(_:language:cli:)` AppleScript et JavaScript, `orders(in:)` pour la fiche,
   `osascriptArguments` (analyse des options de `osascript`).
2. **Exécution** `AlfredScriptRunner` : texte des types 6 et 7 traduit ; `PATH` préfixé par le dossier
   de l'`osascript` de Roadie ; `/usr/bin/osascript ` remplacé dans le texte qui cite Alfred.
3. **Commandes** `roadie workflow alfred ORDRE …` (CLI) : `search` et `trigger` passent au démon
   (`workflow.alfred`), `set`, `remove`, `reload`, `reveal` agissent sur place ;
   `roadie workflow osascript …` traduit et exécute `/usr/bin/osascript`.
4. **Réglages gardés** : `AlfredWorkflow.load` fusionne `~/.roadies/workflows-settings/<id>.json` ;
   l'index tient compte de sa date.
5. **Démon** : `workflow.alfred` → barre rouverte (`search`) ou déclencheur (`trigger`, réutilise
   `runWorkflowCommand`), journal `launcher.alfred_call`.
6. **Fiche** : ordres trouvés et non traduits à la place de « parle à Alfred ».

## Fichiers touchés
`AlfredBridge.swift` (nouveau), `AlfredScriptRunner.swift`, `AlfredWorkflow.swift`,
`AlfredWorkflowIndex.swift`, `AlfredCompatibility.swift`, `CLICommandRouter.swift`,
`TargetModeRuntimeController.swift`, `Tests/RoadieDaemonTests/Spec093BridgeTests.swift`.

## Constitution
- XVIII : traduction O(n) sur le texte du script ; fiche O(f × n).
- XIX : une seule unité nouvelle (texte pur + options d'`osascript`) ; déclencheur, barre et version
  réutilisés ; pas de réglage ajouté (la traduction n'a pas d'inconvénient connu à désactiver :
  `alfred_workflows` coupe déjà les workflows d'Alfred).
- XX : la traduction est textuelle et bornée aux formes relevées ; limites écrites (scripts
  compilés, chemins complets dans les fichiers externes, `action`/`browse`).

## Risques
- Une expression AppleScript contenant ` in workflow ` dans une chaîne : découpage faux ; rare, test
  dédié de la forme du corpus seulement.
- `doShellScript` en JavaScript exige les ajouts standard : l'objet les active sur l'application
  courante.
