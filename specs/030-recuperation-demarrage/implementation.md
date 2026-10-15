# Implémentation — Session 030

## Cause et correction

La première passe stable du LayoutMaintainer récupère les fenêtres candidates sans
scope par le parking existant. La garde de topologie précède cette récupération.
Le service de parking accepte le relevé déjà capturé : en production le fournisseur
rejouable évite une seconde énumération AX. Les relevés vides et les permissions
refusées ne déclenchent aucun parking. Une arrivée tardive est traitée par une passe
normale, sans boucle ni nouveau contrôleur.

## Validation

- Avant correction : 4 tests ciblés, 2 en échec (démarrage et arrivée tardive).
- Après correction : les 4 tests ciblés passent.
- Suite complète : 1470 tests, 157 suites, aucun échec.
- Relecture du diff : 2 fichiers de production, aucun nouveau mécanisme de placement.

## Installation à préserver

La version actuellement installée a le même UUID Mach-O que la Release de la
session 029-resize-rail, dont les changements ne sont pas encore intégrés à main.
L'installation 030 doit conserver ces changements, sans modifier son dossier de travail.
