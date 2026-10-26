# Modèle de données 089

- `AlfredEntry.kind` : + `.listFilter`, `.fileFilter`.
- `AlfredTrigger { workflow, objectUID, kind (.hotkey | .external | .fileAction | .universal |
  .fallback), name, triggerID?, acceptsFiles, acceptsText, acceptsURLs, acceptsMulti, fileTypes,
  argument (hotkey) }`.
- `AlfredAutomationTask { uid, name, script, scriptType, settings: [AlfredUserSetting],
  inputType, inputMulti, inputOverride?, outputType, folder }`.
- `LauncherFileQuery { scopes, types, fields, limit, includeSystem }` (077 généralisée).
- `LauncherActionList.Row.workflow(AlfredTrigger)` ; `LauncherList.Row.fallback(AlfredTrigger, String)`.
- Commandes du démon : `workflow.run { id, object, argument?, variables }`,
  `workflow.trigger { id, trigger, argument?, variables }`.
