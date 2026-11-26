# Spec 168 — Saut direct dans les dialogues « Ouvrir / Enregistrer sous »

## Contexte & Problème
Lorsqu’une application macOS ouvre une boîte de dialogue standard `NSOpenPanel` ou `NSSavePanel` (Ouvrir, Enregistrer sous, Exporter, Joindre un fichier), le dossier proposé par défaut correspond rarement au dossier de travail courant. L’utilisateur doit naviguer manuellement dans l’arborescence ou ouvrir le Finder.

## Exigences fonctionnelles
- **FR-001 (Interrupteur dédié)** : Réglage booléen `experimental.target_mode.file_dialog_jump` (alias `[launcher] file_dialog_jump`), activé par défaut (`true`), exposant un interrupteur explicite dans Paramètres. Quand il vaut `false`, aucune détection de dialogue fichier n’est exécutée (coût zéro) et aucun verbe ni suggestion dédiée n’apparaît.
- **FR-002 (Détection pure et bornée)** : À l’ouverture du lanceur uniquement (zéro polling), Roadie inspecte la fenêtre active / feuille `AXSheet` de l’application au premier plan pour identifier un dialogue fichier (`open` ou `save`).
- **FR-003 (Suggestions en tête de barre vide)** : Lorsqu’un dialogue fichier est actif, la barre vide affiche en priorité une section « Aller au dossier dans ce dialogue » regroupant les dossiers ouverts dans la stage / récents, sans doublon.
- **FR-004 (Verbe dédié & Entrée directe)** : Sur tout fichier ou dossier trouvé dans le lanceur alors qu’un dialogue fichier est actif, le verbe `.useInFileDialog` (« Utiliser dans ce dialogue » / « Jump to folder in dialog ») est proposé en priorité et déclenché par `Entrée`. Si la cible est un fichier, le saut vise son dossier parent.
- **FR-005 (Navigation non destructive)** : La navigation utilise le panneau natif macOS *Aller au dossier* (`⌘⇧G`) puis écriture Accessibilité du chemin (avec validation `Entrée`), en préservant le nom du fichier saisi dans un dialogue « Enregistrer sous » et sans modifier le presse-papiers utilisateur.
- **FR-006 (Diagnostic & sécurité)** : Aucun chemin privé n’est journalisé dans `events.jsonl`. En cas de dialogue fermé ou incompatible, un refus clair est renvoyé sans action destructrice.

## Scénarios Gherkin (TDD)
- **Scénario 1 (Interrupteur désactivé)** : Étant donné `file_dialog_jump = false`, même si une fenêtre `AXSheet` « Enregistrer » est active, aucun contexte de dialogue n’est injecté et `Entrée` sur un dossier conserve le verbe `.open`.
- **Scénario 2 (Détection & résolution dossier)** : Étant donné une feuille `AXSheet` avec titre « Enregistrer sous » ou identifiant `save-panel`, la détection identifie `.save` ; pour un fichier `/a/b/doc.pdf`, la cible résolue vaut `/a/b`.
- **Scénario 3 (Verbe prioritaire dans le lanceur)** : Étant donné `activeFileDialog != nil` et `file_dialog_jump = true`, `verbs(for: .file(...))` place `.useInFileDialog` en tête et `fileVerb` retourne `.useInFileDialog`.
