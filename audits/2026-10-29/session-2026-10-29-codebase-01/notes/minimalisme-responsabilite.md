# Minimalisme et responsabilité future

Potentiel minimalisme : ~10 lignes suppressibles à comportement constant, mesurées sur un échantillon
(recherche des appelants de fonctions d'enrobage), pas sur tout le dépôt :
- `LauncherBookmarkStore.load(browsers:now:)` et `LauncherWebHistoryStore.load(browsers:days:now:)` :
  aucun appelant depuis la session 123 (remplacés par `loadIndex`) : ~6 lignes.
- `LauncherWebHistory.matches(_:in pages:excluding:limit:)` : appelée seulement par les tests : ~3 lignes.
- `UILanguage.configFileText` recopie le chemin de `RoadieConfigLoader.defaultConfigPath()` : 1 ligne.
- `ConfigFileEditor.readLiteral` n'a plus d'appelant en production ; elle sert d'oracle aux tests de
  l'index. La garder est justifié tant que l'équivalence est testée (et F-LITERAL-EMPTY le montre).

Responsabilité future : le code récent est commenté en français avec ses complexités, ses bornes et ses
références de session, ce qui réduit la charge de relecture. Trois fichiers dépassent 2 000 lignes
(LayoutMaintainer 4 331, TargetOverlayPresenter 3 570, TargetModeRuntimeController 2 271) dans un module
de 62 730 lignes : la charge cognitive augmente avec chaque session du lanceur. Le volume ajouté depuis le
27 octobre (+8 913 lignes) sert des fonctions demandées (reprise d'Alfred, traduction). La traduction
en lot (~1 300 textes) a été outillée et relue ; un texte traduit ne sert pas d'identifiant (comparaisons
vérifiées). L'audit ne peut pas établir ce que l'auteur humain comprend de chaque invariant.

Observabilité : `EventLog` reçoit des événements sans saisie de l'utilisateur pour les ordres à Alfred
(FR-007) et les chronométrages de la barre ; la rotation des journaux existe (FileAdministration). Les
échecs silencieux relevés : F-SPOTLIGHT (aucun message) et commandes système sans retour d'erreur.
