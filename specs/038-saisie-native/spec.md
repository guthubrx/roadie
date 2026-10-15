# Session 038 — Saisie native et sélection des suggestions

Statut : Implémentée, testée et installée. Correction demandée le 15 octobre 2026.

## Besoin

La boîte de recherche/commandes doit se comporter comme un champ de texte macOS.
Dans `/settings`, les suggestions doivent se choisir avec Haut/Bas ou à la souris.
La version actuelle dessine une chaîne avec un faux curseur et intercepte les
touches ; les raccourcis d'édition partent parfois vers l'application sous-jacente.

## Acceptation

1. Champ AppKit éditable et sélectionnable : clic, glisser de sélection, caret,
   Maj-flèches, navigation par mot, ⌘A/C/X/V/Z et Maj-⌘Z, ⌥⌫, ⌘⌫, caractères
   accentués. Une sélection remplacée ne laisse aucun fragment ancien.
2. Haut/Bas parcourent les suggestions d'une commande non vide ; Tab insère le
   choix, Retour accepte le choix puis exécute. L'historique reste accessible lorsque
   la saisie est vide ou sans suggestion. Un clic insère la suggestion exacte.
3. Aucun raccourci d'édition ni clic de suggestion n'agit sur l'application en dessous.
   Un clic extérieur ferme la boîte et passe une seule fois à l'application visée.
4. Conserver la position, les tailles de police, le compteur, l'affichage des erreurs,
   les messages, la recherche, Tab, Échap et les actions Retour/⌘Retour/Maj-Retour.
   Les majuscules saisies restent du texte dans le champ natif.
5. La fermeture libère le champ et le clavier ; les commandes différées et la fenêtre
   de réglages s'ouvrent après nettoyage. Pas de changement des stages ni des réglages BTT.
6. Tests ciblés puis suite complète ; circuit natif clavier/souris et diaporama.
   Installation signée et redémarrage de Roadie uniquement, T3 conservé.
