# Validation 104

- Lecture réelle (test jetable, retiré) : cinq profils Firefox trouvés avec leurs noms ; 172 signets dans
  « Moi » ; 28 onglets ouverts décodés ; Safari 16 signets ; Chrome 1 ; 301 signets Firefox et 92 icônes
  en 0,38 s à froid.
- Tests ajoutés : `Tests/RoadieDaemonTests/Spec104BookmarksTests.swift` (6 tests) : dossiers, étiquettes et
  mots-clés de Firefox sur une base construite, profils de `profiles.ini` et de `Profile Groups`, Chrome et
  Safari, correspondance sans doublon, session LZ4 de Firefox.
- Appui sur un onglet Firefox par l'accessibilité : à essayer (événement `launcher.firefox_tab`).
