# Validation153 — livrée

Le 3 novembre 2026. Version active : UUID 89D4F279-C3AC-3320-9CD3-2F8E138E1B6D, PID 73065. Santé 5/5 après nettoyage. Certificat SHA-1 78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration utilisateur inchangée à l'octet près.539 empreintes Sources/Tests conformes après intégration. Sources 072e628a84db5f5a91755eac4e6a1b7b4b5da9a5 intégrées et poussées sur main ; les commits de clôture ne changent que la documentation. Aucune nouvelle release publique.

## Comportement et tests
Une copie initiale figée suit le pointeur. Le rendu, la visibilité et la taille sont réglables dans Effets. Défauts : contenu,85 % de visibilité,50 % de taille. La destination garde son choix indépendant contour/réel. Aucune opacité privilégiée de fenêtre tierce, aucun changement des protections macOS. Une seule capture initiale, plafond de 2 millions de pixels. Après 300 ms sans résultat, repli sur un déplacement visible de la vraie fenêtre. Les résultats tardifs ne réactivent pas la copie.

Dernière suite :2 512 tests / 380 suites verts en160,280 s. Derniers tests ciblés :80 tests verts, dont le mode contour avec et sans suivi des voisines. Cas couverts : migration et bornes de configuration, géométrie et ratio, mouvement natif contraint au bord, refus d'un resize ou d'un cadre immobile, clic AppKit livré deux fois puis nouveau clic, capture absente/tardive/annulée, remplacement d'un geste, retrait immédiat du visuel au relâchement et à Échap avec écrivain bloqué.

Deux revues indépendantes en lecture seule. Les relecteurs n'avaient ni shell ni diffGit et n'ont exécuté aucun test. Première revue : un défaut moyen confirmé et plusieurs risques faibles. La seconde lecture de e3f41477 confirme D1/D2 corrigés sans nouveau défaut concret prouvé. Le responsable a ensuite ajouté deux gardes : restauration de la source en mode contour sans suivi des voisines ; retrait du visuel si le writer invalide sa génération/portée. Pas de troisième revue de ces dernières lignes. Voir revue.md pour les réponses et limites.

## Essais natifs et preuves
Glisser natif et Ctrl + glisser observés : source 673 × 934 points, copie 337 × 467 points, alpha WindowServer0,850000024. Le panneau change de position, puis disparaît au relâchement. Un passage vers l'écran externe a montré la copie en x = 2050, y = −106 ; Échap l'a retirée et a restauré exactement les deux cadres fictifs.

Diaporama à six étapes : captures fictives de la versionB755B94B, avant les deux derniers gardes de cycle de vie. Appuis injectés puis réellement observés par un tap CGEvent ; coordonnées converties dans les captures Retina. Aucun clic humain ni DOM isTrusted revendiqué. Deux annotations orange vérifiées, première action en pause, navigation, dernière étape, lecture/pause et zoom contrôlés. Les images et manifestes originaux restent horsGit. Les captures qui contenaient d'autres fenêtres sont exclues.

Les deux essais tardifs de changement de stage pendant le geste sont exclus : les points injectés n'ont pas atteint le client fictif attendu dans une session utilisée en parallèle. Aucun succès natif ni défaut produit n'en est déduit. Le parcours automatisé n'a pas obtenu la fenêtre des paramètres : aucun changement de valeur via cette interface n'est revendiqué. Catalogue FR/EN, bornes, migration et écriture sont couverts par tests.

## Charge et limites
Quatre captures acceptées sur la génération mesurée :29,1 /31,0 /42,6 /94,8 ms. Pas de capture par mouvement. Deux gestesCtrl + glisser :0,37 s CPU sur4,66 s, soit7,95 % d'un cœur pour roadied entier. Repos adjacent :0,05 s sur2,01 s, soit2,48 %. Activité normale incluse, sans attribution exclusive à la copie. RSS : 132 544 → 133 792 Kio : série trop courte pour conclure sur une fuite. GPU et WindowServer non mesurés. Aucun gain ni fréquence d'images garanti.

La capture peut partir au simple clic sur un titre admissible ; ce coût des clics seuls n'est pas mesuré. Si le SDK ne rend jamais la main, le garde global reste occupé pour éviter une file de requêtes. Les gestes suivants gardent leur repli visible jusqu'au retour réel. Une image de 2 Mpx représente environ 8 Mo RGBA hors allocations système. Les références d'image sont libérées à la fin du geste.

## Intégration et nettoyage
Branche 153 locale et distante supprimée. Deux tâches de revue terminées, résultats lus et accusés. Worktrees 6abac5e3 et 7727b969 retirés après contrôle : aucun changement, aucun fichier ignoré ni processus utilisateur, commits intégrés dans origin/main. Branches de revue retirées avec contrôle du SHA attendu. Aucun checkout partagé distant déplacé.

Build supprimé :1 444 796 Kio, environ1,38 Gio. Six exécutables et deux applications fictives supprimés après arrêt. Le worktree de conversation actif est conservé, détaché sur main. Installation, retour arrière 152 et originaux/manifestes/reçus privés conservés. La stage validation153final contient Finder 21825 : elle est préservée pour ne pas déplacer ou retirer une fenêtre utilisateur. Les autres stages de validation vides ont été supprimées. La stage interne 6 reste active.

Bridget a refusé la publication initiale du diff non commité (publication_refused). Incident conservé ; catalogue des spécialistes visible vide, donc aucun destinataire de maintenance confirmé et aucun envoi à un ancien identifiant. Les revues ont ensuite utilisé les commits publiés. Les reçus BTT de séries longues ont parfois annoncé une échéance ; seuls les fichiers durables terminés ont été retenus, sans rejeu aveugle.

Originaux et reçus privés : /Users/moi/.local/state/roadies/validation/2026-11-03-153. Preuves du glisser vérifiées ; limites des réglages UI et des derniers essais natifs explicites ci-dessus.
