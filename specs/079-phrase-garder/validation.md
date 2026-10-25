# Validation 079

## Tests
- `Spec079PhraseTests` (7 tests) : `fire perso gauche` = `fire perso left`, pas de phrase sans fin
  reconnue, ici, nouvelle stage, bureau N, écran N, nom de deux mots, début unique de 3 lettres,
  verbe selon l'objet (envoyer, aller à, déplacer une stage, rien pour une application vers un
  bureau) ; abréviations : seuls applications et fichiers, stage nommée exigée, commande avec
  guillemets échappés, stage retrouvée par son nom après un déplacement, noms de 1 à 12
  caractères, enregistrement et remplacement.
- Suite complète : 2 008 tests / 270 suites réussis.

## Essai réel (commande que génère ⌘S)
- `roadie launch /System/Applications/Calculator.app --here --position float` : ouverte ici,
  position expirée. Cause : fenêtre à taille fixe sans stage ; une fenêtre non gérée de la bonne
  application est désormais acceptée. Calculette refermée (elle ne tournait pas).
- `roadie launch /tmp/roadie-079/droite.txt --here --position right` : placée, puis expirée deux fois.
  Données ajoutées au journal (`lastSeen`) : focus lu = KeePassXC, alors que TextEdit l'avait ;
  le relevé sans suivi du focus était périmé. Avec le relevé normal : `launcher.position`
  (« warp right: no structural change », la fenêtre était déjà à droite). Délai porté à 20 s
  (TextEdit à froid : environ 7 s). Document fermé, TextEdit refermé, fichiers supprimés.

## Limites
- Phrase et étape « Garder » non essayées au clavier (pas de frappe simulée).
- `warp` déplace dans l'arbre ; dans une stage à une fenêtre, gauche et droite ne changent rien.
- Preuves : diaporama non produit (écrans privés).

## Correction après livraison (relecture avant audit)
La boucle de position refaisait un relevé complet avec suivi du focus toutes les 300 ms (jusqu'à
66 relevés). Elle lit désormais le focus en direct (`focusedWindowID`) et ne fait un relevé sans
effet de bord qu'au changement de focus, ou toutes les 1,2 s. Essai réel : `--position full` →
`toggle maximize on: changed=true`. Suite complète relancée.
