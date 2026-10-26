# Contexte - audit V15 des sessions 087 à 091 (révision 1 = 01789d19)

Périmètre : diff 50e36a43..01789d19 (sources : 28 fichiers, 3 559 lignes ajoutées ; tests : 17 fichiers),
appelants relus dans `TargetOverlayPresenter.swift` (session de recherche), `TargetModeRuntimeController.swift`
(contexte du lanceur, exécutions), `CLICommandRouter.swift`, `SearchInputPanel.swift`.

Biens à protéger : fenêtres et stages de l'utilisateur, presse-papiers, fichiers, autorisation
Accessibilité du démon, saisies tapées (historique), données des workflows d'Alfred (lecture seule).

Acteurs et points d'entrée : l'utilisateur au clavier (barre Capslock+F), la ligne de commande
`roadie workflow|launcher`, les workflows installés par l'utilisateur (scripts tiers), les tâches
d'automatisation téléchargées (dépôt public alfredapp, BSD-3).

Invariants relus : un script de workflow tourne dans son propre groupe de processus, signaux par
défaut, entrée vide, sortie bornée (5 Mo), délai 10 s, arrêté à la frappe suivante ; le journal ne
contient ni saisie ni sortie ; le dossier de préférences d'Alfred n'est jamais écrit ; une nouvelle
stage d'un lot est créée une seule fois ; `/` reste au mode commande sauf chemin reconnu.

Limites : barre non essayée au clavier (aucune frappe simulée) ; ouverture d'adresse dans une stage,
lot de fenêtres réelles et Audio Switcher non lancés (effets visibles chez l'utilisateur) ; Swift sans
CodeQL ni linter configuré ; revue indépendante refusée par Bridget (`project_mapping_unknown`,
`origin_request_invalid`).
