# Complexité, minimalisme et responsabilité

Décodage O(k), k ≈ 65 clés ; fusion des touches O(a), a = 13 actions, dictionnaire.
Édition : deux parcours O(L) pour une clé migrée, L = taille du fichier ; aucun scan
par fenêtre, aucune écriture ajoutée au tick. Lecture d'alias par dictionnaire O(1).
Complétion : O(n × s), s borné aux sous-commandes d'une commande (<15), table <100 ;
chaque mot est filtré avant interpolation zsh. Version : O(k) parties numériques.
Réseau : une requête, 5 s, garde 6 s et annulation ; mémoire du corps liée à la réponse
GitHub, pas de promesse de borne en octets. L'API est fixe, publique, sans jeton ni données
utilisateur. Le JSON est limité aux deux chaînes utiles. Pas de cache persistant ajouté.

Potentiel minimalisme : non mesuré globalement ; aucun nouvel emballage de service ni
paquet. Réutilisations : Config/TargetModeConfig, éditeur, catalogue, routeur et build.
Initialiseur partagé nécessaire car superDecoder de TOMLKit est fatalError ; nestedContainer
est implémenté. Le routage d'alias respecte les clés inconnues de l'éditeur générique.
Code retiré : deux émissions de journal de coordonnées ; gros fichier réduit de 70 lignes
par déplacement pur. 21 diaporamas retirés après archive vérifiée ; images utiles conservées.

Mainteneur : ADR 032 expose priorité, migration par clé et limite de retour à l'ancien
binaire. Une fixture peuplée et Mirror obligent à représenter nil/tableaux futurs dans
la garde. Commentaires et lignes voisines testés par comparaison exacte, y compris 20 valeurs.
Aucun gain de CPU/latence du produit mesuré ou revendiqué. Les recettes de préparation
restent des archives et les limites de transaction entre plusieurs fichiers ne valent pas
une garantie atomique globale en cas de panne ; leurs sorties normales ont été vérifiées.
