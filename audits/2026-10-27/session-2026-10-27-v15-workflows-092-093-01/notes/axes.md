# Axes

- Sécurité : aucune authentification ni réseau entrant ; l'`osascript` de Roadie ne s'applique qu'aux
  scripts des workflows (variable `PATH` de leur environnement) et passe tout texte sans ordre à
  Alfred tel quel ; commande `roadie` citée par `shellQuote` ; AppleScript généré : expressions
  d'origine dans `quoted form of`, chemin de la commande échappé ; JavaScript : valeurs citées pour le
  shell (apostrophe testée). Réglages gardés : nom de fichier sans « / ». Dossier d'Alfred jamais écrit.
- Logique : grille (sources, surcharge, présélection, voisins, Retour), déclencheur `externalid`,
  traduction des formes du corpus, exécution réelle osascript, mesure réelle (déclencheur servi par
  Roadie, deux chemins d'`osascript`), corpus de 102.
- Concurrence : effet de grille sur le fil principal ; barre ouverte annulée avant la grille (essai
  concurrent observé dans le journal) ; `shim` écrit une fois (`static let`), index sous verrou.
- Complexité : traduction O(n) ; voisins O(n/|pas|) ; disposition O(t) ; fiche O(f × n) ; regex
  compilées une fois.
- Tests : 2 110 tests (24 neufs : 11 grille, 13 ordres), deux exécutions réelles d'osascript.
- Architecture : deux types purs (`AlfredGridView`, `AlfredBridge`) ; grille par les lignes
  `.workflowItem` existantes ; présentateur +80 lignes, contrôleur +40.
- Minimalisme : aucune dépendance ; `SearchBarLayout.makeGrid` et voisins par rang au lieu du sélecteur
  (arbitrages A1, A2 écrits) ; potentiel : ~0 ligne suppressible à comportement constant.
- Observabilité : `launcher.workflow_grid`, `launcher.alfred_call` sans texte de l'utilisateur.
- Traçabilité : FR 092 (10) et 093 (7) reliés à des tests ou limites (validation.md).
