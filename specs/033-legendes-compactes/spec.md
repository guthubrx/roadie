# Session 033 — Légendes compactes et dépôt Outlook

## Fiche Synthèse

Spec: 033-legendes-compactes
Titre: Légendes lisibles sous les aperçus et dépôt dans Teams
Statut: In Progress
Priorité: P1
Tâches: 4/5 (80%)
Tests: 1549/1549 (100%)

Validation utilisateur le 2026-10-15 : légende sous les vignettes, numéro et nom,
14 points, contraste renforcé, écart de 4 points réglable, perspective optionnelle.
Affichage temporaire par double Alt droit. Places nommées vides conservées.
Ajout explicite à la même session : regarder les deux déplacements Outlook refusés
à 10 h 28, depuis le bas gauche vers le bas de Teams sur l'écran externe.

## Acceptation

1. Légende sous la forme « 3 — Com », sous l'aperçu, avec taille indépendante des
   autres détails du rail. Texte compact, lisible, borné à la largeur du rail.
2. Option pour suivre la perspective de la vignette ; texte droit par défaut.
   Écart vignette–légende réglable ; calcul à partir du contour réellement dessiné.
3. La légende ne se superpose pas à l'aperçu ni à la stage suivante. Hauteur compacte
   commune aux emplacements vides et occupés, sans suppression ni renumérotation.
4. Conserver apparition et disparition temporaires, double Alt droit et double Alt gauche.
5. Diagnostiquer les essais de 10 h 28 et reproduire le défaut avant correction.
   Le dépôt Outlook sous Teams doit produire la disposition annoncée et la garder
   au cycle suivant, avec la fenêtre de gauche agrandie dans sa colonne.
6. Tester, installer une version qui conserve les corrections déjà installées,
   vérifier la signature, le redémarrage, la santé et les deux rails.

## Preuves initiales du dépôt

Deux `window_drag_apply` à 08:28:09Z et 08:28:12Z (10:28 heure locale), fenêtre 614,
opération insertDown, changed=true. Chacun produit une seule commande AX sur Outlook,
aucune sur Teams. Les cadres observés ensuite restent identiques. État incident
conservé localement ; aucune donnée personnelle des fenêtres dans les artefacts Git.
