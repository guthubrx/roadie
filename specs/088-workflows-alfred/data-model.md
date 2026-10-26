# Modèle de données 088

- `PlistValue` : `string | int | double | bool | array | dict | data | date`, avec lecteurs
  `string(_:)`, `int(_:)`, `bool(_:)`.
- `AlfredWorkflow { id (nom du dossier), bundleID, name, description, version, folder, source
  (.alfred | .roadie), disabled, objects: [String: AlfredObject], connections: [String:
  [AlfredConnection]], variables: [String: String], userConfig: [AlfredUserSetting], prefs }`.
- `AlfredObject { uid, type (sans le préfixe « alfred.workflow. »), config: [String: PlistValue] }`.
- `AlfredConnection { destination, modifiers: Int }`.
- `AlfredEntry { workflow, objectUID, kind (.scriptFilter | .keyword), keyword, withSpace,
  argument (.required | .optional | .none), title, subtitle, icon }`.
- `AlfredItem { uid?, title, subtitle, arg: [String], icon: AlfredIcon?, valid, match?,
  autocomplete?, isFile, mods: [Int: AlfredMod], copyText?, quickLookURL?, variables }` ;
  `AlfredMod { arg?, subtitle?, valid?, variables }`.
- `AlfredScriptFilterResponse { items, variables, rerun: Double?, skipKnowledge }`.
- `AlfredRun { workflow, objectUID, arg: [String], variables, modifiers }` → moteur.
- `AlfredEffects` (protocole) : `openURL`, `openFile(app:)`, `reveal`, `copy`, `notify`,
  `playSound`, `speak`, `writeFile`, `closeBar`, `showBar(text)`, `log`, `runScript`.
- `AlfredCompatibilityReport { workflow, state (.complete | .partial | .unusable), missing:
  [String], mentionsAlfred, keywords }`.
- `LauncherList.Row.workflowItem(AlfredEntry, AlfredItem)`, `.workflowKeyword(AlfredEntry)`.
- Réglages : `TargetModeConfig.workflowsEnabled` (`workflows_enabled`, vrai),
  `alfredWorkflows` (`alfred_workflows`, vrai).
