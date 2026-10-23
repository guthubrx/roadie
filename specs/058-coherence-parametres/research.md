# Recherche et diagnostic 058
- SettingsView : réglages non booléens placés sous le titre ; descriptions de
  bornes ajoutent une ligne ; largeurs de contrôles indépendantes.
- SettingsCollectionEditor : champ systématiquement sous son libellé, booléen
  affiché seul ; répétition Entrée N ; aides permanentes.
- SettingsSwitcherProfilesView : chaque LabeledContent calcule son alignement
  séparément ; menus ont des largeurs différentes.
- Popover : texte dans une frame de largeur maximale, sans adaptation explicite
  de hauteur ni défilement. Cause compatible avec la coupure signalée.
- Décision : conserver les contrôles natifs et les tailles de police utilisateur.
  Utiliser une géométrie commune mesurant les sous-vues, sans nouvelle dépendance.
Sources Apple consultées le 23 octobre 2026 :
https://developer.apple.com/documentation/swiftui/layout
https://developer.apple.com/documentation/swiftui/layout/sizethatfits(proposal:subviews:cache:)
https://developer.apple.com/documentation/swiftui/layout/placesubviews(in:proposal:subviews:cache:)
https://developer.apple.com/design/human-interface-guidelines/settings
