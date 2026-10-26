# Spécification 088 - Workflows Alfred dans le lanceur, étape 1 : mots-clés, listes et schéma

Demande du 26 octobre 2026 (`/my.specify-all 086 a 091`) : « la capacité à supporter les
[workflows] d'Alfred, ce qu'on pourrait supporter bien sûr, ceux qui ne font pas référence
explicite à Alfred ». Réponses données avant : le format est documenté, le reprendre est permis
(CJUE C-406/10) ; chaque workflow garde sa licence ; Roadie n'en livre aucun.

## Demande reformulée
Roadie lit, sans les modifier, les workflows installés dans Alfred, et ceux que l'utilisateur
installe pour Roadie. Dans Capslock + F, leurs mots-clés et leurs Script Filters marchent comme
dans Alfred : même liste, mêmes touches par ligne, même chaîne d'actions derrière Retour.
L'étape 1 couvre les entrées tapées (mot-clé, Script Filter) et le moteur du schéma : actions,
sorties et utilitaires. Une commande dit, pour chaque workflow, ce qui marche et ce qui manque.

## Mesure de départ (research R1)
101 workflows réels (55 de l'équipe Alfred, 42 de la communauté, 4 de l'utilisateur). Avec les
briques de cette étape, 57 % ont au moins une entrée qui marche entièrement, 26 % marchent en
entier. L'étape 2 (089) vise 93 % et 82 %.

## Dépendances
SPEC-073 à 077 (lanceur, verbes, variantes, fichiers), SPEC-085 (touche des raccourcis).
Suite : SPEC-089 (déclencheurs, filtres, tâches d'automatisation).

## Exigences
- **FR-001 Sources.** Workflows du dossier de préférences d'Alfred (dossier synchronisé suivi,
  lecture seule) et de `~/.config/roadies/workflows/`. Un workflow ou un objet désactivé dans
  Alfred est ignoré. Réglages : `workflows_enabled` (vrai), `alfred_workflows` (vrai). Index relu
  quand un `info.plist` change, au plus une fois par ouverture de la barre.
- **FR-002 Mot-clé tapé.** Une saisie dont le premier mot est le mot-clé d'un Script Filter ou
  d'une entrée Keyword (espace exigée ou non, argument requis, facultatif ou interdit selon le
  workflow) montre seulement les lignes de ce ou ces workflows, sous leur nom.
- **FR-003 Mot-clé en cours.** Dès 2 lettres, les mots-clés qui commencent par la saisie, ou dont
  le titre correspond, sont proposés dans une section « Workflows » (titre et sous-titre du
  workflow, icône). Retour ou Tab complète la saisie par le mot-clé ; Retour lance directement une
  entrée sans argument.
- **FR-004 Script Filter.** Le script tourne avec l'interpréteur de son type (bash, zsh, zsh sans
  fichiers de démarrage, osascript AppleScript et JavaScript, python3, ruby, perl, script
  externe), dans le dossier du workflow, avec le texte après le mot-clé en `argv` ou dans
  `{query}` selon le workflow (échappement respecté). Une nouvelle frappe arrête le script en
  cours ; attente de 100 ms entre frappes (premier caractère immédiat) ; arrêt après 10 s ;
  5 Mo de sortie au plus. Un interpréteur absent (php, python2) donne une ligne d'erreur claire.
- **FR-005 Réponse.** Format JSON d'Alfred : `items` (`uid`, `title`, `subtitle`, `arg` texte ou
  liste, `icon` chemin/`fileicon`/`filetype`, `valid`, `match`, `autocomplete`, `type`, `mods`,
  `text.copy`, `quicklookurl`, `variables`), `variables`, `rerun`, `skipknowledge`. Ancien
  format XML `<items>` lu aussi. Avec « Alfred filtre les résultats », le script tourne une fois
  et la barre filtre par `match` ou `title`.
- **FR-006 Lignes.** Titre, sous-titre, icône. Tenir ⌘, ⌥, ⌃ ou ⇧ montre le sous-titre de ce
  modificateur ; une ligne non valide sous ce modificateur ne fait rien. Tab : `autocomplete`
  (précédé du mot-clé). ⌘C : `text.copy`, sinon `arg`. ⌘Y : `quicklookurl`. Ordre du script,
  puis classement appris par `uid` sauf `skipknowledge`. Raccourcis 1 à 9 comme les autres lignes.
- **FR-007 Retour.** Ligne valide : la barre se ferme et l'argument et les variables (workflow <
  liste < ligne < modificateur) suivent les connexions de l'objet avec le modificateur tenu.
  Ligne non valide : son `autocomplete` remplace la saisie.
- **FR-008 Schéma.** Objets exécutés : Run Script (sortie = argument suivant ; sortie JSON
  `alfredworkflow` lue), Run NSAppleScript, Open URL, Open File, Reveal in Finder, Launch Apps/Files,
  Default Web Search, Copy to Clipboard, Post Notification, Play Sound, Speak, Write File,
  Arguments and Variables, Conditional, Junction, Split Arg, Join Args, Transform, Replace,
  Filter, Delay, Random, JSON Configuration, Hide Alfred (fermer la barre), Show Alfred
  (rouvrir la barre avec un texte), Debug (journal), Expression. Remplacements `{query}`,
  `{var:nom}`, `{const:…}` connus. Un objet non pris en charge arrête la chaîne avec une
  notification « Roadie ne prend pas encore en charge : <brique> ».
- **FR-009 Environnement.** Variables `alfred_*` documentées (dossiers de données et de cache du
  workflow, identifiant, nom, version, mot-clé, préférences, version d'Alfred installée), variables
  du workflow, réglages de l'utilisateur (`prefs.plist`, sinon valeurs par défaut), plus
  `roadie_version`. Dossiers de données : ceux d'Alfred pour un workflow d'Alfred (même état que
  dans Alfred), ceux de Roadie pour un workflow de Roadie.
- **FR-010 Commandes.** `roadie workflow list [--json]` : nom, identifiant, source, mots-clés,
  état (complet, partiel, inutilisable), briques manquantes, mention d'Alfred. `roadie workflow
  check DOSSIER` : même relevé pour un dossier de workflows, avec les totaux. `roadie workflow
  install FICHIER.alfredworkflow [--replace]` et `roadie workflow remove ID` (dossier de Roadie
  seulement).
- **FR-011 Confidentialité.** Le journal ne garde ni saisie, ni titre, ni argument : identifiant
  du workflow, durée, code de sortie, nombre de lignes, brique manquante.

## Critères de réussite
- `emoji heart` dans la barre : les 46 lignes d'Emoji search avec leurs icônes ; Retour copie
  l'émoji choisi ; ⌥ Retour copie son code `:nom:`.
- `roadie workflow check /tmp/roadie-wf-corpus/…` sur le corpus de 101 : au moins 55 % avec une
  entrée complète (mesure du plan : 57 %).
- Une frappe ne bloque jamais la barre : le script tourne hors du fil principal ; 30 frappes
  rapides ne laissent aucun processus derrière elles.

## Hors périmètre (089 ou jamais)
Raccourcis, déclencheurs externes, actions sur fichier, recherches de repli, filtres de liste et de
fichiers, tâches d'automatisation, frappes simulées, grand texte, Terminal (089). Vues Texte,
Grille, Image, PDF, snippets, Alfred Remote, éditeur de workflows : écartés.
