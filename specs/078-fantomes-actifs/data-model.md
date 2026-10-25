# Modèle de données 078

- `LauncherPreviewRequest { stage: StageScope, incoming: WindowID?, appPath: String? }` ;
  `incoming` nil = fenêtre à ouvrir (fantôme).
- `LayoutPreviewHold` : échéance (`Date?`) sous verrou ; `hold(for:)`, `release()`, `isHeld`.
- Aperçu actif (contrôleur) : requête, cadres relevés avant, stage de retour, fantôme (cadre NS).
- `LauncherGhost { frame: CGRect, icon: NSImage? }` dessiné par l'overlay.
