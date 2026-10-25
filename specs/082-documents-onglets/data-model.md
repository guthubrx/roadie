# Modèle de données 082

- `LauncherOpenItem { kind: document|tab, windowID, bundleID, appName, title, detail, url?,
  tabIndex?, browserWindow? }` ; `id` : `doc:<windowID>` ou `tab:<bundle>:<fenêtre>:<rang>`.
- `LauncherList.Section.openItems`, `Row.openItem(LauncherOpenItem)`.
- `LauncherSearchContext.loadOpenItems`, `activateOpenItem`.
