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


## Charge observée
Deux gestesCtrl+glisser :0,37sCPU sur4,66s, soit7,95% d’un cœur pour le processus roadied entier. Repos adjacent :0,05s sur2,01s, soit2,48%. Activité normale du daemon incluse ; ce n’est pas une attribution exclusive à la copie. RSS132544→133792Kio : série courte, sans conclusion sur une fuite. GPU etWindowServer non mesurés. Le reçu BTT a annoncé une échéance alors que le fichier durable benchmark.json confirmait la fin ; aucune relance du même essai n’a été faite.

Les deux clients fictifs sont arrêtés. Les stages validation153a et validation153b ont été retirées après vérification qu’elles ne contenaient que ces clients. La stage interne6 est restaurée, puis l’écran externe refocalisé. Aucun stage externe choisi par l’utilisateur n’a été remplacé.


## Validation après revue
La fin immédiate du visuel, le délai300ms et le rejet de sa capture tardive passent les72 tests ciblés. Suite finale :2512 tests /380 suites réussis en68,050s. Version finale chargée : UUID B755B94B-02A3-3709-8885-D7C3E9018F38, PID23423, santé5/5. Glisser natif etCtrl+glisser rejoués sur cette version : copiealpha0,85 présente pendant le mouvement, absente au relâchement. Les six images du diaporama proviennent de cette dernière version. Configuration utilisateur toujours identique à la copie d’avant153. La première revue est traitée dans revue.md ; une seconde lecture ciblée des corrections sera demandée.


## Activation définitive
UUID89D4F279-C3AC-3320-9CD3-2F8E138E1B6D, PID73065, santé5/5 avant intégration.80tests ciblés puis2512tests /380suites verts en160,280s après les derniers gardes. Le coût de cette suite inclut la charge du poste, sans comparaison de vitesse revendiquée. Les captures du diaporama restent celles de la versionB755B94B, avant ces deux gardes ; leur légende le précise. Les deux essais tardifs de changement de stage pendant le geste sont exclus : les points injectés n'ont pas atteint la fenêtre fictive attendue. Aucun défaut produit ni succès natif n'en est déduit.

Le client fictif final est arrêté. La stage validation153final contient désormais Finder21825 ; elle est conservée pour ne pas déplacer ou retirer une fenêtre utilisateur. La stage interne6 reste active et les autres stages de validation vides ont été supprimées. La configuration reste identique à la copie d'avant153. Les originaux exclus restent privés.


## LivraisonGit et nettoyage
Sources intégrées et poussées surmain à072e628a84db5f5a91755eac4e6a1b7b4b5da9a5.539 empreintesSources/Tests identiques avant et après intégration. Configuration utilisateur inchangée à l’octet près, certificat conservé. Santé5/5 après suppression du build.

Branche153 locale et distante supprimée. Les deux tâches de revue sont terminées, leurs résultats lus et accusés. Leurs worktrees6abac5e3 et7727b969 sont retirés après contrôle : aucun changement, aucun fichier ignoré, aucun processus utilisateur, commits intégrés dansorigin/main. Les branches de revue sont retirées avec contrôle duSHA attendu ; aucun checkout partagé déplacé.

Build supprimé :1444796Kio, environ1,38Gio. Six exécutables de validation et deux applications fictives retirés après arrêt de leurs processus. Le worktree de conversation actif est conservé, détaché surmain, ainsi que l’installation, le retour arrière152 et les originaux/manifestes/reçus privés. La stage validation153final contenantFinder21825 est conservée. Aucun fichier de preuve brute ni configuration privée ajouté àGit.

Le commit final de clôture ajoute uniquement cette documentation et les statuts, sans changement de code. Les limites de validation native et des réglages restent celles indiquées ci-dessus.
