# Étude AltTab gratuit et Pro

Sources officielles consultées le 23 octobre 2026 :
- https://alt-tab.app/features : fenêtres, aperçus, actions, filtres, clavier, accessibilité, gestes et CLI.
- https://alt-tab.app/pricing : Pro = recherche, styles icônes/titres, taille automatique, jusqu'à neuf raccourcis.
- https://alt-tab.app/faq : source GPL-3.0, licence commerciale des binaires distribués ; limites Stage Manager distinct de Roadie.
- https://github.com/lwouis/alt-tab-macos : HEAD étudié 2d4f4c8fab1eeb3ec08f32abdf541713b68d89d0 ; app installée 11.9.2.

Code étudié : ProFeature, WindowFilterResolver, WindowOrderResolver, SearchTestable/SearchModeResolver, WindowCaptureEvents, windowserver/README et ShortcutActions.
AltTab filtre par Space macOS, écran et application. Aucun lien avec StageStore Roadie trouvé dans ces chemins. Hypothèse structurelle expliquant les incohérences : fenêtres garées hors vue et appartenance Roadie inconnues d'AltTab. Aucun incident exact reproduit pendant cette étude.

Réemploi Roadie : SnapshotService.readerSnapshot, StageStore/PersistentStageMember, activation de WindowBookmarkCommandService.focus, focus AX qui désminimise, cache ScreenCaptureKit RailThumbnailStore, réglages génériques et champ natif. Nouveau : MRU global borné, session de sélection stable, transaction d'activation sans signet temporaire, panel et raccourcis avec relâchement.
Difficulté faible à moyenne : styles/recherche/dimensionnement. Moyenne : profils/réglages. Forte : activation contexte, ordre récent réel et gestion touches. Pas de promesse de performance mesurée.
