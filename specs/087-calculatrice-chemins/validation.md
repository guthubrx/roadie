# Validation 087

## Tests
- `Spec087CalculatorTests` (5) : priorités, `^` à droite, moins unaire, `,`/`.`, `×` `÷` `%`, fonctions
  après `=`, saisies non calculables (nombre seul, `12*`, `1/0`, `0/0`, `1.2.3`, texte), 10 000 saisies
  aléatoires sans plantage, Maj + chiffre écrit dans une saisie vide ou de calcul (touche Maj).
- `Spec087PathTests` (4) : `/` commande ou chemin (commandes et alias contre la racine), `~`, découpage,
  complétion, lecture d'un dossier temporaire (filtre, cachés, dossiers d'abord, nom exact en tête),
  liste « Chemin » et ligne « Calcul » en tête.
- `Spec085PickModifierTests` adapté : le raccourci Maj + 2 est testé dans une recherche ordinaire.
- Suite complète : 2 046 tests / 282 suites réussis (avant le test de liste ajouté : relancé dans la
  suite ciblée, 2 047 au total).

## Installation
`make install`, `make restart` : PID 3593, santé 5/5 (`accessibility=true`), signature
`com.roadie.roadied` au même certificat.

## Limites
- Barre non essayée au clavier (aucune frappe simulée) : essai utilisateur proposé (quickstart).
- Le choix « Maj + chiffre écrit dans une saisie vide » retire Maj + 1 sur la barre vide (lignes de la
  081) : les flèches et le clic restent.
- Preuves : diaporama non produit (frappe impossible à simuler, écrans privés).

## Correction du 27 octobre 2026
- Signalé : `=sqrt(2)` impossible à taper en AZERTY avec Maj pour les raccourcis. Maj + é choisissait
  la 2e ligne, parce que les lettres de `sqrt` faisaient sortir la saisie des « caractères de calcul ».
- Corrigé : une saisie commencée par `=` compte comme un calcul en cours (`LauncherCalculator.isTyping`).
- Tests : `shiftDigitTypesInACalculation` couvre `=sqrt(` et `=2*pi+` ; suite complète 2 086 tests /
  292 suites réussis. Installé : PID 9780, santé 5/5, certificat `roadied-cert` conservé.
- Non vérifié : frappe réelle dans la barre (essai utilisateur).
