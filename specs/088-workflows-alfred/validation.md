# Validation 088

## Tests
- `Spec088WorkflowModelTests` (5) : lecture d'un workflow d'essai (objets, flèches, branches,
  variables, réglages, `prefs.plist`), mots-clés (espace, argument requis/facultatif/interdit, titre),
  remplacements, valeurs plist, dossier synchronisé d'Alfred, index qui ignore un workflow désactivé.
- `Spec088ScriptRunnerTests` (6) : 7 bits d'échappement, interpréteurs par type, argv et
  environnement `alfred_*`, mode `{query}`, annulation qui arrête tout le groupe de processus,
  délai et plafond de sortie.
- `Spec088ResponseTests` (4) : JSON (mods combinés, icônes, texte, variables), XML, filtrage
  d'Alfred (4 modes), sortie `alfredworkflow`.
- `Spec088EngineTests` (6) : modificateurs (repli sans flèche propre), conditions et branche sinon,
  utilitaires, brique manquante et boucle bornée, Write File, fiche de compatibilité.
- `Spec088LauncherTests` (3) : identités des lignes, section Workflows, Script Filter réel puis ⌥ Retour.
- Suite complète : 2 070 tests / 287 suites réussis (après la convergence aussi).

## Mesures
- Corpus de 102 workflows (`/tmp/roadie-wf-corpus/mixed2` : 55 dépôts officiels complets, 43
  `info.plist` communautaires avec scripts externes remplacés par des témoins, 4 de l'utilisateur) :
  `roadie workflow check` → 24 complets, 54 avec une entrée complète (53 %). Sans les 4 workflows en
  php ou python 2, absents de macOS et donc cassés aussi dans Alfred : 54/98 (55 %). Manques restants :
  tâches d'automatisation (28), déclencheurs externes (15), raccourcis (14), appels externes (12),
  actions universelles et sur fichier (10 chacune), vues Texte (8) : session 089.
- `roadie workflow list` sur ce Mac : Audio Switcher, Emoji search, Reminders partiels,
  System Settings Explorer inutilisable (grille, appel externe ; parle à Alfred).

## Défauts trouvés et corrigés pendant la session
- Le démon (et le lanceur de tests) ignore SIGTERM ; un script lancé en héritait et ne pouvait plus
  être arrêté (essai : `sleep 5` vivant après le délai de 0,3 s). Les signaux sont remis par défaut.
- Une accolade d'un texte JSON (`utility.json`) avalait le `{query}` suivant.
- Un script externe en chemin absolu était cherché dans le dossier du workflow.

## Installation
PID 80109 puis réinstallation après convergence ; santé 5/5, signature conservée.

## Limites
- Barre non essayée au clavier (pas de frappe simulée) : `emoji heart` reste à essayer (quickstart).
- Mesure R8 (droits Accessibilité d'un script lancé par le démon) reportée à la 089 : elle demande
  `roadie workflow run`, qui lance un workflow dans le démon.
- Contre-revue Bridget refusée (`project_mapping_unknown`).
- Preuves : diaporama non produit (frappe impossible à simuler, écrans privés).
