# Session 117 : vue Texte des workflows

## Besoin

Brique `alfred.workflow.userinterface.text` (Alfred 5.5) : 9 workflows sur 102 du corpus en ont besoin
(OpenAI, Wolfram|Alpha, Notes, Simple Diff, Network Quality…). Roadie l'annonçait « non prise en charge ».

## Réglages relevés (application Alfred 5, `AlfredWorkflowUserInterfaceText.nib`, et corpus)

- Source `inputtype` : 0 argument reçu, 1 script (`inputfile` : fichier exécutable du workflow), 2 fichier
  (`inputfile`, sinon l'argument).
- Comportement `behaviour` : 0 sélectionnable, 1 modifiable, 2 Markdown.
- Champ de saisie `scriptinput` : 0 aucun, 1 au-dessus, 2 au-dessous ; il relance le script.
- Police `fontmode` : 0 système, 1 thème, 2 chasse fixe. `footertext`, `loadingtext`, `stackview`.
- JSON du script (aide « Text View JSON Format ») : `response`, `footer`, `actionoutput`, `variables`, `rerun`,
  `behaviour.response` (replace, append, prepend, replacelast), `behaviour.scroll` (auto, start, end),
  `behaviour.inputfield` (clear, select).

## Règle

- Fenêtre (panneau qui n'active pas Roadie mais reçoit le clavier), titre du workflow, pied de page.
- Markdown : titres, paragraphes, listes, citations, code, traits, images (chemin relatif au dossier du
  workflow ou du fichier) ; gras, italique, code et liens dans les lignes.
- Script : premier passage avec l'argument reçu ; Retour seul dans le champ relance avec la saisie ; une
  réponse avec `rerun` relance la même saisie ; une réponse plus ancienne qu'une nouvelle saisie est ignorée.
- Retour hors du champ (avec ou sans touches tenues) ferme et envoie le texte entier à la suite du schéma
  depuis la brique, avec les bits de touches d'Alfred. Texte modifiable : ⇧↩ et ⌥↩ écrivent une nouvelle
  ligne ; ↩ aussi s'il n'y a pas de flèche sans touche. `actionoutput` envoie la réponse.
- Échap ferme. Journal `launcher.workflow_text` sans texte.

## Limites

- `stackview` (Échap revient à la barre) et la taille de texte globale d'Alfred ne sont pas repris.
- Pas de correcteur orthographique (`spellchecking`).
