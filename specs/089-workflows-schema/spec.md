# Spécification 089 - Workflows Alfred, étape 2 : déclencheurs, filtres et tâches d'automatisation

Demande du 26 octobre 2026 (`/my.specify-all 086 a 091`) : suite de la 088 ; l'utilisateur
voulait aussi comprendre et pouvoir utiliser « les workflows compliqués » (le schéma complet).

## Demande reformulée
Les workflows qui démarrent autrement que par un mot-clé tapé marchent aussi : raccourci
clavier, appel externe, action sur un fichier ou un texte, recherche de repli. Les filtres de
liste et de fichiers, les tâches d'automatisation officielles d'Alfred, le grand texte, les
frappes simulées et le Terminal sont exécutés. Un workflow peut appeler Roadie, et Roadie peut
lancer n'importe quel objet d'un workflow depuis BetterTouchTool.

## Mesure de départ (research R1)
Corpus de 101 : 93 % avec au moins une entrée complète, 82 % entiers, 71 % entiers et sans aucune
mention d'Alfred. Restent hors d'atteinte : vues Texte (9), Remote (4), snippets (3), PDF (2),
Grille (2), tampon (1), Image (1).

## Dépendances
SPEC-088 (index, exécution, schéma), SPEC-077 (fichiers), SPEC-090 (lignes de repli, qui
reprennent les recherches de repli des workflows quand elle est livrée).

## Exigences
- **FR-001 Déclencheurs externes.** `roadie workflow trigger ID DÉCLENCHEUR [ARGUMENT]
  [--var nom=valeur]` lance un déclencheur externe (`trigger.external`) ; la sortie « Call
  External Trigger » d'un workflow fait de même, vers lui-même ou un autre workflow.
- **FR-002 Raccourcis.** `roadie workflow run ID OBJET [ARGUMENT]` lance n'importe quel objet par
  son `uid`. `roadie workflow list --hotkeys` liste les raccourcis déclarés (touches d'Alfred,
  argument attendu : sélection, presse-papiers, texte, aucun) avec la commande à coller dans
  BetterTouchTool ; Roadie ne capture pas lui-même ces raccourcis. L'argument « sélection macOS »
  est lu par l'accessibilité, sinon par une copie simulée.
- **FR-003 Actions sur fichier et universelles.** Les déclencheurs `trigger.action` et
  `trigger.universalaction` deviennent des verbes « Workflow : <titre> » des fichiers (selon les
  types acceptés) et, pour les actions universelles sur texte ou adresse, de la saisie tapée.
- **FR-004 Recherches de repli.** Les `trigger.fallback` apparaissent comme lignes de repli en bas
  de liste (avec la ligne web de la 090 quand elle est livrée ; seules sinon), avec le texte tapé.
- **FR-005 Filtre de liste.** `input.listfilter` : ses éléments fixes (titre, sous-titre, argument)
  filtrés par la saisie après le mot-clé.
- **FR-006 Filtre de fichiers.** `input.filefilter` : recherche Spotlight du workflow (types,
  portée, champs, limite), lignes de fichiers avec leurs verbes Roadie.
- **FR-007 Tâches d'automatisation.** `automation.task` exécute la tâche officielle (dépôt public
  `alfredapp/automation-tasks`, BSD-3) : script, type, réglages et entrée multiple. Les tâches ne
  sont pas livrées avec Roadie : `roadie workflow tasks update` télécharge l'archive publique dans
  `~/.roadies/alfred-tasks/` ; sans elle, la brique manque et la fiche le dit.
- **FR-008 Autres briques.** Dispatch Key Combo (touches simulées), Large Type (panneau de grand
  texte, Échap ferme), Browse in Terminal, Terminal Command, Run Shortcut (Raccourcis Apple),
  File Utility (copie, déplacement, corbeille), Dialog (confirmation), Browse in Alfred et
  Action in Alfred (barre rouverte sur le chemin, mode chemin de la 087).
- **FR-009 Fiche.** `roadie workflow list` et `check` tiennent compte de ces briques.

## Critères de réussite
- Corpus de 101 : au moins 90 % avec une entrée complète et 80 % entiers (`roadie workflow check`).
- Audio Switcher : `roadie workflow list --hotkeys` donne ses raccourcis et leur commande ; la
  commande bascule la sortie audio et affiche la notification.
- Un verbe « Workflow : … » apparaît sur un fichier quand un workflow déclare une action sur fichier.

## Hors périmètre
Vues Texte, Grille, Image, PDF ; snippets ; Alfred Remote ; tampon de fichiers d'Alfred
(la sélection multiple de Roadie arrive en 091) ; éditeur de workflows ; capture des raccourcis par
Roadie.
