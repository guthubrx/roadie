# Vérifications de régression du code figé

Sources/tests/build : 575 fichiers comparés par SHA-256 à la copie d'audit, identiques.
- ./scripts/test --no-parallel : 2549 tests dans 388 suites, code 0, 81,709 s.
- Cas intermittent 151 : premier passage complet en échec ; recontrôle isolé 19 tests,
  puis nouvelle suite complète réussis. Aucun succès attribué au premier passage.
- python3 -I -B -m unittest discover -s scripts/tests : 29 tests, OK, dont transmission
  d'identité clean / dirty fichier suivi / dirty fichier non suivi dans un vrai Git isolé.
- 26 tests ciblés 155, 5 suites ; 7 tests Launcher (lecture prioritaire et fichiers réels).
- Cas avant Launcher : 7 tests en échec, 14 assertions ; cas après réussi. SuperDecoder
  TOMLKit non implémenté remplacé par nestedContainer après lecture de la dépendance.
- Comparaison exacte de 20 modifications : succès après correction de la conservation
  du commentaire scalaire ; observation des lignes réelles conservée hors Git.
- zsh -n accepté ; commandes et sous-commandes générées depuis commandTable testées.
- Bundle temporaire : commit abc12345 écrit et relu ; statut ancien sans champ accepté.
- Guardes AX relues : CFGetTypeID précède les conversions ; 5 gardes dans le fichier.
- Journal : 366 lignes préservées ; extraction : 69 lignes sans changement, 4392 restantes.
- Numéros ADR uniques ; zéro sauvegarde suivie ; zéro chemin personnel dans les README.
- Couverture : 71,30 % des lignes mesurées avant compléments, pas de chiffre extrapolé.

Les logs bruts correspondants sont conservés dans runs/external-proofs, ignorés par Git.
Le build Release a son propre reçu borné dans runs (outil custom). Pas de lint Swift ajouté ;
compilation stricte Swift 6 et analyse manuelle. Pas de parcours graphique nouveau à prouver.
L'activation de 0.14.0 et la conservation du certificat seront qualifiées en T053, hors audit du code.

Build Release : runner custom révision 1, code 0 en 266,935 s, aucune instance survivante signalée.
