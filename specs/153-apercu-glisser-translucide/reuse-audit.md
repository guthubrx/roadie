# Réutilisation153

- Tap, propriété du geste et relâchement natif : WindowDragReorderController, pas de nouveau hook souris.
- Géométrie observée sans AX : NativeResizeRuntime.visibleFrame, identité CG/PID stricte.
- Cibles et contexte figés : DropPreviewEngine et DropPreviewContext.
- Écritures et restauration : LiveDropPreview et InteractiveFrameDispatcher ; pas de writer parallèle.
- Captures : RailThumbnailStore/ScreenCaptureKit ; partager les métadonnées, garder une requête par source.
- Fenêtre de rendu : panneau AppKit non activant avec contenu graphique ; nouvelle responsabilité distincte pour la copie mobile choisie par l’utilisateur.
- Paramètres : EffectsConfig et SettingsCatalogEffects, catalogue de choix existant et traductions FR/EN.

Pas de dépendance nouvelle, pas de réglage macOS modifié. Les APIs d'opacité privilégiées sont exclues après sonde native et lecture des sources de Yabai. Risques à couvrir : déplacement natif repris tardivement, ratio obsolète, session annulée pendant une capture et click/release avalé.
