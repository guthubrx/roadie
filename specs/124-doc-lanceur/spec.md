# Session 124 : documentation du lanceur et des workflows d'Alfred

## Besoin

Le projet a beaucoup évolué (lanceur des sessions 073 à 123, workflows d'Alfred), mais le README, les guides et la
description GitHub (« About ») présentaient encore surtout le gestionnaire de fenêtres. L'utilisateur veut une
documentation à jour qui mette en avant le lanceur et rappelle que les workflows d'Alfred demandent le Powerpack,
payant, alors que Roadie les fait tourner gratuitement. Il veut des captures sans aucune donnée privée.

## Règle

- README FR/EN : présentation en deux piliers (gestionnaire de fenêtres et lanceur), captures, comparaison factuelle
  avec Alfred (prix vérifié sur alfredapp.com le 29 octobre 2026 : 34 £ ou 59 £), mention claire que le lanceur
  n'est pas dans la version publiée 0.10.0. Partie installation et référence conservée.
- Nouveaux guides `docs/fr/launcher.md` et `docs/en/launcher.md` ; index des docs mis à jour ; phrase périmée de
  `features.md` sur les vues Texte, Image, PDF et Alfred Remote corrigée.
- Captures dessinées par le vrai moteur de rendu de Roadie avec des données d'exemple : icônes des applications
  d'Apple, vignettes et fichiers inventés, fond dégradé synthétique. Aucune capture d'écran réelle. Générateur :
  `Tests/RoadieDaemonTests/Spec124DocScreenshotsTests.swift`, inactif sans `ROADIE_DOC_SHOTS_DIR`.
- « Gratuit » et « code source public », jamais « open source » : le dépôt n'a pas de licence.
- Alfred est cité comme marque de Running with Crayons Ltd, sans affiliation.
