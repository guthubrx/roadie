# Validation153 — en cours

72 tests ciblés dans10 suites réussis. Après adaptation des attentes du catalogue :30 tests ciblés verts, puis2508 tests dans380 suites verts en77,044s. Aucun changement153 encore chargé. La configuration utilisateur reste inchangée. Une copie initiale figée suit le pointeur ; destination indépendante. Défauts :85% de visibilité,50% de taille. Revue indépendante et essais natifs restent à faire.

Le premier build a relevé un import manquant. La compilation des nouveaux tests a relevé trois erreurs de déclaration, corrigées. Deux attentes de tests étaient inadéquates : le fixture151 écrasait les touches désactivées et la cible153 ne changeait pas de disposition. La configuration d’origine est désormais conservée et le test vise une autre tuile. Les72 tests ciblés passent après correction. Aucun essai raté n’est revendiqué comme preuve.


## Version active et essais
Version installée et rechargée, PID67379, UUID207DF647-E413-33B8-84F2-BA65CAEB2DE4. Santé5/5. Certificat SHA-1 78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration utilisateur non modifiée. Dernière suite :2510 tests dans380 suites réussis en70,259s. Après les dernières corrections natives,89 tests ciblés verts avant cette suite.

Glisser normal et Ctrl+glisser : copie337×467 points pour une source673×934, alpha WindowServer0,850000024. Le panneau change de position pendant le geste, puis disparaît au relâchement. Une seule image initiale figée. Passage natif vers l'écran externe : copie constatée en x2050,y−106, puis Échap retire le panneau et restaure exactement les deux cadres fictifs. Les captures visibles ne portent que sur les fenêtres fictives. Appuis injectés puis effectivement relevés par un tap CGEvent : coordonnées natives converties dans la capture Retina, pas de coordonnées supposées ni de clic humain revendiqué.

Quatre captures acceptées sur cette génération :29,1 /31,0 /42,6 /94,8ms. Pas de capture par mouvement. Ce petit échantillon ne donne aucune garantie de fréquence ni de délai global. CPU/GPU non mesurés séparément à ce stade. Une image est bornée à2millions de pixels, soit environ8MoRGBA hors allocations système.

Deux défauts supplémentaires identifiés en natif : clic AppKit livré deux fois, qui annulait sa propre capture ; grande fenêtre contrainte au bord inférieur alors que le pointeur continue de descendre. Le premier down est maintenant conservé pour le même geste. Le mouvement natif accepte un axe bloqué au bord, et deux observations successives cohérentes compensent le retard des premières images. Tests dédiés : doublon puis nouveau clic ; mouvement contraint ; resize, cadre immobile et mauvaise direction exclus. L'essai trop tôt au démarrage, avant disponibilité du tap, est exclu. Aucune causalité avec le redémarrage du Mac n'est affirmée.

## Preuves et limites
Diaporama autonome à six étapes, deux appuis observés, images fictives originales intactes horsGit. Première annotation orange vérifiée ; contrôles avant/arrière, dernière étape, lecture/pause et zoom vérifiés. Les premières captures qui contenaient d'autres fenêtres sont exclues. RéglagesFR/EN, bornes et migration couverts par tests. Le parcours automatisé n'a pas obtenu la fenêtre des paramètres : aucun changement de valeur via cette interface n'est revendiqué. Aucun changement de protections macOS.

Bridget a refusé la publication du diff non commité (publication_refused). Signalement conservé horsGit : aucun spécialiste de maintenance visible dans les recherches du catalogue, donc aucun envoi à un ancien identifiant. Revue sur commit publié à demander. Ne pas transformer les tests du parent en validation indépendante.
