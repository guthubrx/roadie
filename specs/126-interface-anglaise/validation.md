# Validation 126 - Interface en anglais

- `tr(fr, en)` dans `Sources/RoadieCore/UILanguage.swift` ; environ 250 textes traduits dans la barre, les verbes,
  les commandes `/`, les workflows, le sélecteur et la vue d'ensemble.
- Effet visible en français : la grille d'un workflow dit « Chargement… » au lieu de « Loading… » ; le sous-titre
  d'une stage dit « Bureau 1 · 2 fenêtre(s) » au lieu de « Desktop 1 - 2 fenêtre(s) ».
- Tests : `Spec126InterfaceLanguageTests` (détection, verbes et bureaux trouvés dans les deux langues, commandes
  système). Suite complète : 2 276 tests / 332 suites réussis.
- Captures : 10 en anglais et 10 en français, générées par `Spec124DocScreenshotsTests`, relues à l'écran
  (recherche, verbes, phrase, calcul, sélecteur, vue d'ensemble).
- Installation signée `roadied-cert`, PID 60738, santé 5/5. Ce Mac est en français : l'interface installée reste
  en français.
- Non vérifié : la barre réelle sur un Mac réglé en anglais (seul le rendu des captures montre l'anglais).
- Preuves : pas de diaporama, les clics simulés sont refusés sur ce poste ; les captures anglaises sont produites
  par le moteur de rendu réel.
