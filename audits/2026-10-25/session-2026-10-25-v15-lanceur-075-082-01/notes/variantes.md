# Recherche de variantes

- F4 (écritures du classement à clé arbitraire) : `rg "recordVisit\\(" Sources` → presenter
  (`file:` des seules réponses Spotlight, dossier personnel), alias et projets (choix explicites de
  l'utilisateur), `rememberFolder` (corrigé). Aucune autre variante.
- F1 (appels externes au chargement) : `rg "osascript|NSAppleScript|LauncherBrowsers.run" Sources`
  → `openItems` (chargement) et `activate` (Retour explicite), `performFile` lance `qlmanage` sur
  geste. Seul le chargement est implicite.
- F2 (I/O synchrone sur chemin chaud) : `rg "JSONPersistence.write" Sources/RoadieDaemon/Launcher*`
  → classement (choix), alias (⌘S), projets (commande), mémoire (déplacement). Seule la mémoire est
  liée à un événement fréquent ; bornée.
- Fichiers réels écrits par les tests : `rg "init\\(path: String = \"~" Sources` → tous les magasins
  du lanceur passent par `TestEnvironment.launcherFile` ; empreintes des fichiers réels identiques
  avant et après la suite.
