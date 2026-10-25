# Validation 077

## Tests
- `Spec077FilesTests` (8 tests) : recherche rapide et seuils, chemins montrés (hors `~/Library`,
  cachés, `node_modules`), ordre d'usage, section Fichiers après Fenêtres dans l'ordre de
  Spotlight, espace en tête = fichiers seuls, verbes et variantes d'un fichier, identité de
  stage retrouvée (nom réel, place pour « Stage N »), ⌘C sans sélection et ⌘Y.
- Suite complète : 1 997 tests / 265 suites réussis.

## Essai réel
- `roadie launch /tmp/roadie-077/essai.txt` : ouvert dans TextEdit. Deuxième appel avant
  correction : `scanned 9/9/0`, document non lu (valeur `CFURL`). Après correction : `focused`,
  `scanned 1/1/1`, aucune seconde fenêtre.
- Relevé des documents (research R6) : TextEdit oui ; Chrome, T3 Code adresse web ; Firefox,
  Thunderbird, Teams, iTerm2, KeePassXC non ; Office non vérifié.
- Documents d'essai fermés, TextEdit refermé (il ne tournait pas), fichiers supprimés.
- Installation signée, santé 5/5.

## Corrige 076
L'identité de stage du classement utilisait aussi les noms générés « Stage N », répétés d'un
bureau à l'autre : seuls les vrais noms (règle SPEC-067) servent désormais, sinon la place.

## Limites
- Recherche Spotlight et ligne Fichiers non essayées dans la barre au clavier (pas de frappe
  simulée) ; ⌘C, ⌘Y : tests du panneau seulement.
- Une application qui ouvre le fichier dans un onglet d'une fenêtre existante ne déplace rien.
- Firefox n'expose pas son document : un fichier ouvert dans Firefox n'est pas retrouvé.
- Preuves : diaporama non produit (écrans privés).
