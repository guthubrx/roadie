# ADR 025 — Observer hors du fil principal, terminer le placement explicitement

Date : 1 novembre 2026. Statut : accepté. Session 149.

## Contexte
Le relevé périodique des fenêtres attend les applications par Accessibility sur le fil principal. Les journaux montrent des passes de plusieurs secondes ; un échantillon natif confirme ce parcours. Les lecteurs graphiques disposent déjà d’une acquisition asynchrone avec validation de la publication, des écrans, de la configuration et du fichier d’état.
Les transitions de cadres rendent « différé » à la passe. Leur résultat final ne revient pas à la mémoire des échecs du maintainer, ce qui permet de répéter une demande déjà échouée.

## Décision
Réutiliser l’acquisition du SnapshotService en mode producteur, sans partager son travail avec les lecteurs : le fournisseur rejouable du maintainer doit conserver exactement son relevé pour les réparations internes d’une passe. Le relevé et la lecture de focus attendent hors du fil principal ; la réconciliation, les arbres et les décisions restent sur le fil principal. Une modification des commandes, du contexte ou un geste en cours invalide la publication attendue.
TickScheduler ne prépare qu’une passe à la fois. Les demandes restent regroupées pendant l’attente ; les blocages sont revérifiés à la reprise. observationMs distingue l’attente de la durée de la passe, dueLagMs conserve le retard précédant l’acquisition.
Après un relevé invalidé, les reprises attendent 50, 100, 200, 400, 800, 1600 puis 2000 ms. Une nouvelle demande ne contourne pas ce délai. Cette borne évite les acquisitions en boucle, mais peut ajouter jusqu’à deux secondes après des rejets répétés. La demande et les échéances restent conservées jusqu’à une observation valide. Les rejets et la reprise sont journalisés.
La barre emploie l’acquisition lecteur existante, avec quatre essais bornés et annulation. Échap pendant l’attente révoque l’ouverture. Une acquisition indisponible ne devient pas un faux modèle vide.
Le dispatcher transmet la génération du lot terminé. Seuls les résultats de la génération finale des transitions reviennent au maintainer. Les images intermédiaires et les lots annulés restent exclus. Les échecs réutilisent la mémoire et les événements par fenêtre existants.

## Conséquences
L’attente d’une application ne retient plus l’interface pendant l’acquisition. L’application peut rester lente : aucun gain de sa propre réponse n’est promis. Quelques lectures AX directes des gestes et des commandes restent synchrones. Les tests contrôlent sérialisation, invalidation et mémoire des échecs ; les mesures réelles sont décrites dans la validation. Aucun nouveau thread permanent, dépendance ou réglage.

Les notifications de cadre réutilisent également l’identité locale des fenêtres déjà suivies. Leur relecture AX est asynchrone, avec une opération active et une dernière demande par fenêtre. Le filtrage d’écho reste sur MainActor et ne confirme aucun refus issu d’une génération plus récente que la lecture. L’essai natif a montré que déplacer le seul relevé périodique ne suffisait pas.

La sauvegarde périodique de restauration réutilise également readerSnapshot. Sa tâche est unique, annulable et revérifie Mission Control après l’attente. Les sauvegardes synchrones de démarrage et de fermeture restent réservées à ces phases explicites.
