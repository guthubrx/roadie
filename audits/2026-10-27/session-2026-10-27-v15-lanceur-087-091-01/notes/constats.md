# Constats

## F1 MEDIUM (corrigé) - copie simulée de la sélection : presse-papiers non texte perdu
`TargetModeRuntimeController.selectedText` (raccourci de workflow, argument « sélection », repli
quand l'accessibilité ne donne rien) gardait `board.string(forType: .string)` puis, après le ⌘C
simulé, `clearContents()` et remettait ce seul texte. Un presse-papiers d'image ou de fichiers était
donc vidé. Code d'avant : `notes/avant-F1-selectedText.swift.txt` (empreinte du fichier dans
`notes/avant-F1-sha.txt`). Correction : `PasteboardSnapshot` garde toutes les représentations de
chaque élément et les remet. Validation : `AuditV15LanceurTests.pasteboardSnapshotRestoresEveryRepresentation`
(PNG et texte remis, presse-papiers vide laissé vide), suite complète 2 086 tests.

## F2 INFO (confirmé, mesuré) - un script de workflow obtient l'autorisation Accessibilité du démon
Mesure R8 : script lancé par `roadie workflow trigger` → `AXIsProcessTrusted() = true` (PPID =
roadied) ; depuis le Terminal → `false`. Même situation que dans Alfred. Atténuations écrites :
lecture des seuls workflows installés par l'utilisateur, réglages `workflows_enabled` et
`alfred_workflows`, avertissement dans Paramètres > Recherche et la documentation.

## Observations sans défaut
- Échappement de `{query}` par les 7 bits d'Alfred, aussi pour Terminal Command ; AppleScript reçoit
  le texte entre guillemets échappés (`applescriptEscaped`).
- Remplacements dans un JSON : accolades du JSON laissées telles quelles (défaut trouvé et corrigé
  pendant la 088, test).
- Groupes de processus : défaut « SIGTERM ignoré par héritage » trouvé et corrigé pendant la 088
  (essai `sleep` vivant après le délai, puis arrêt en 0,33 s).
