# Journal — session 026

## Résultat en cours de validation

Tab complète le titre du résultat sélectionné sans action. Le mode commande
accepte la proposition choisie. Le rendu de la barre est séparé du dessin des
badges : largeur fixe de 640 points, ancrage bas-centre, compteur à droite,
police système proportionnelle et contour neutre de 0,5 point.
Les tailles indépendantes de la session 025 restent applicables immédiatement.

## Vérifications effectuées

- Baseline : trois tests reproduisent cinq erreurs (géométrie et sélection Tab).
- Première correction : 62 tests ciblés dans cinq suites, succès.
- Première suite complète : 1 381 tests, 147 suites, succès en 8,239 s après compilation.
- Suite complète après corrections de revue : 1 384 tests, 147 suites, succès en 6,685 s après compilation.
- Vérification finale après ancrage de l'écran : 1 384 tests, 147 suites, succès en 5,918 s après compilation.
- Cinq rendus du vrai composant AppKit hors écran : barre vide, recherche,
  commandes, texte long et police de 48 points. Commandes, texte long et grande
  police inspectés ; la troncature laisse le compteur visible et séparé.
- Rendus finaux régénérés après les corrections ; barre vide et compteur de recherche inspectés.

## Revue indépendante

Premier tour : un cas de Tab après navigation Control pendant un cycle reste
à corriger ; le premier test couvrait seulement la navigation avant le premier Tab.
Le nouveau test vérifie aussi le retour au choix initial après un tour complet.
Les deux tests reproduisent quatre erreurs avant correction. Le cycle conserve
son préfixe mais désarme l'avance après une navigation explicite ; Tab accepte
alors le choix courant. Les 65 tests ciblés passent après correction.

Le paramètre de largeur du contenu a été retiré. Un point discret dans la pastille
indique la lecture en cours. Un titre commençant par `/` est complété avec un espace
initial pour rester en recherche. Les cibles au texte de recherche personnalisé
gardent leur sélection si leur titre ne peut pas servir de requête.

Le rendu hors écran est exécuté par le parent dans un harnais temporaire.
Le reviewer a lu le code ; il n'a ni compilé ni inspecté les captures.

Deuxième tour : cycle de Tab confirmé. Le cas des cellules de grille est hors
du périmètre Caps+F : startTargetsSearch charge les cinq sortes de cibles Roadie
et les éléments d'application ; les cellules restent dans startGridInteractive.
Cette frontière est maintenant explicite dans la spec. La suite complète après
correction est bien passée, pendant ce tour de revue.

L'écran d'ouverture était déjà capturé dans pointerScreen, mais show() relisait
la position de souris à chaque rendu. Le rendu utilise désormais pointerScreen,
pour conserver l'écran même après un déplacement du pointeur sur un autre moniteur.

Troisième tour : aucun défaut bloquant confirmé. Le reviewer vérifie le cycle,
le périmètre des cibles et l'ancrage par lecture ; les deux logs complets
après correction montrent 1 384 tests verts. Le petit delta d'ancrage est
vérifié par lecture et par compilation, sans test miroir supplémentaire.

Les titres `*` et `;` gardent la sémantique existante de recherche globale.
Les lignes de texte internes sont aplaties pour tenir dans les lignes du panneau.

## Livraison

Installation terminée : build release, signature `roadied-cert` conservée,
redémarrage avec PID 81591. Les quatre contrôles de santé sont OK ; configuration,
accessibilité et capture d'écran valides. Le premier contrôle socket a précédé
sa disponibilité au démarrage ; le contrôle suivant est passé sans intervention.
Validation utilisateur : « oui ça fonctionne et c'est propre ». Le choix de police
demandé ensuite est ajouté au périmètre de la session 027.
Les README et références
français/anglais décrivent la navigation et la barre. Changelog dans « À publier » ;
pas de nouvelle release demandée.
