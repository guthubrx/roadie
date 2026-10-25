# Spécification 075 - Touches du lanceur et flottement durable

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`), après la référence Alfred
(`docs/analyses/2026-10-25-reference-alfred.html`) et le cadrage « lanceur propre à Roadie ».
Choix de l'utilisateur : variantes de Retour, ⌘1 à ⌘9, verbes de la fenêtre active, → pour les
actions, et flotter ou tuiler « cette fenêtre » ou « toujours » pour l'application.

## Demande reformulée
Rendre la barre Capslock + F aussi rapide qu'Alfred au clavier : une touche modificatrice
change ce que fait Retour, et la ligne l'annonce avant ; les neuf premières lignes se
choisissent par ⌘ + chiffre ; un raccourci ouvre directement les verbes de la fenêtre active ;
→ en fin de saisie ouvre les verbes comme Tab. Ajouter le choix « cette fenêtre » ou
« toujours pour l'application » pour le flottement, dans la barre et dans le menu Fenêtre.

## Dépendances
SPEC-021 (mode recherche), SPEC-047 (flottement par stage), SPEC-073 et 074 (lanceur, verbes,
destinations), règles générées du menu de barre de titre (`WindowRuleAffinityService`).

## Exigences
- **FR-001 Variantes de Retour.** Sur une application, une fenêtre ou une stage :
  - ⌘ Retour : application → l'ouvrir dans une nouvelle stage du bureau affiché ; fenêtre →
    l'envoyer dans une nouvelle stage ; Roadie y va.
  - ⌥ Retour : application ouverte → amener sa fenêtre préférée dans la stage active ;
    application fermée → l'ouvrir dans la stage active ; fenêtre → l'amener dans la stage
    active. La stage affichée ne change pas.
  - ⌃ Retour : chercher le texte tapé sur le web, adresse réglable (`web_search_url`).
  - Cibles à l'écran : ⇧ Retour clic droit et ⌘ Retour ⌘-clic restent inchangés ; ⌃ Retour
    cherche sur le web.
- **FR-002 Annonce.** Tant qu'une de ces touches est tenue, le détail de la ligne choisie
  devient la description de la variante (ex. « ⌘ ↩ Ouvrir dans une nouvelle stage »). Sans
  variante pour cette ligne, le détail reste inchangé et Retour fait l'action normale.
- **FR-003 ⌘1 à ⌘9.** Les neuf premières lignes choisissables visibles portent « ⌘1 »…« ⌘9 »
  à droite ; ⌘ + chiffre fait leur action par défaut, à toutes les étapes (objets, verbes,
  destinations). La ligne choisie garde son rappel « ⇥ actions ↩ ».
- **FR-004 Verbes de la fenêtre active.** Un raccourci global (défaut Capslock + Maj + F,
  réglable, vide = désactivé) et la commande `roadie target actions` ouvrent la barre
  directement à l'étape des verbes de la fenêtre au premier plan. Sans fenêtre gérée, la barre
  s'ouvre normalement.
- **FR-005 Flèche droite.** → avec le curseur en fin de saisie non vide ouvre les verbes de la
  ligne choisie, comme Tab. Ailleurs, → déplace le curseur comme d'habitude.
- **FR-006 Flotter ou tuiler.** Les verbes d'une fenêtre proposent, selon son état :
  « Faire flotter cette fenêtre », « Toujours faire flotter <App> », « Remettre cette fenêtre
  au tuilage », « Toujours tuiler <App> », « Retirer la règle de <App> ». Le menu Fenêtre de la
  barre de titre propose les mêmes choix « toujours ».
- **FR-007 Règle unique par application.** « Toujours » écrit dans le fichier de règles générées
  (`roadies.generated.toml`), jamais dans `roadies.toml`, sur la même règle que l'affinité
  « Toujours ouvrir cette app ici » si elle existe ; chacune survit à la modification de
  l'autre. Le fichier est relu avant remplacement. L'effet s'applique à toutes les fenêtres de
  l'application, présentes et futures.

## Critères de réussite
- Ouvrir Firefox dans une nouvelle stage : `fire`, ⌘ Retour (deux gestes après le raccourci).
- Amener la fenêtre Outlook ici sans quitter la stage affichée : `out`, ⌥ Retour.
- La description de variante apparaît en moins d'une image (16 ms) après l'appui sur la touche.
- « Toujours faire flotter Firefox » puis « Toujours ouvrir cette app ici » : les deux réglages
  restent dans la même règle, vérifiés par relecture du fichier.
- Aucune régression : 1 976 tests existants réussis.

## Hors périmètre
Tuiler « juste cette fenêtre » quand macOS la fait flotter par nature (dialogue, panneau) :
seule la règle « toujours » est proposée. Recherche de repli et recherches par mot-clé : 077.
