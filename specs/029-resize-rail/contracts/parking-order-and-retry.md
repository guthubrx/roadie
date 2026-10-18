# Contrat : retour d’écran (R3) et reprises bornées (R4)

## Retour d’écran

Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/DisplayParkingService.swift et structure `StageOrigin` dans /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageStore.swift.

1. Utiliser `StageOrigin.position` et les champs existants. Aucun nouveau champ ni tableau d’ordre.
2. Si le placeholder d’origine est intact, le remplacer à sa place actuelle. Cela conserve l’ordre choisi par l’utilisateur pendant l’absence.
3. Pour une copie encore `.parked`, garder l’ancien repli sur la position d’origine bornée aux limites du tableau si le placeholder manque.
4. Conserver les renommages et changements de mode faits pendant l’absence. Si le mode d’origine d’un ancien placeholder est inconnu, le conserver plutôt que l’écraser.
5. Garder le placeholder tant qu’une copie correspondante existe. La matérialisation après 60 s conserve la place du stage dans le scope hôte.
6. Une copie `.restored` ne revient que si un placeholder `.parked` correspondant existe encore dans son bureau/écran d’origine. L’écran correspond par identité physique OU logique. Le retour après 60 s ou une nuit reste possible lorsque ce témoin subsiste.
7. Une ancienne copie `.restored` sans ce placeholder reste où elle est : ses métadonnées ne permettent pas de déduire un retour encore attendu. Une identité physique ou logique qui correspond déjà à l’origine ne relance pas le transfert.
8. Un déplacement explicite vers un écran détache le stage : `.native`, `origin`, `host` et `restoredAt` à `nil`. Respecter aussi les copies déjà natives ou sans origine.
9. Lors d’un déplacement, capturer le caractère automatique du nom avant détachement et réécrire seulement ce nom après choix de l’identifiant final. Conserver les noms personnels. Une destination vide nommée, de mode différent ou avec arbre explicite reste intacte ; allouer un nouvel identifiant pour le transfert.
10. Ne pas fusionner de membres ni écraser une modification utilisateur. Corriger le diagnostic d’origine absente vide localement, sans nouveau format général d’événements.

Les recherches et insertions dans les tableaux restent O(s), s étant le nombre de stages du scope. Aucun état global d’ordre supplémentaire.

Preuves rouge → vert : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029DisplayParkingTests.swift couvre retour court, après matérialisation et après une nuit, placeholder réordonné ou absent, noms/modes modifiés, anciens fichiers, placeholder obligatoire pour une copie `.restored`, copie détachée et idempotence.

## Reprises après refus

Source : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift. Intégration par le parent après gel du lot gestes.

### Constat

Les placements hors arbre ne sont pas tous mémorisés lors d’un refus. Un chemin de focus contourne aussi le budget d’écriture d’arbre. La stabilité peut être réarmée par des écritures échouées. Le diagnostic compte 128 passes en 33,577 s pour la même génération 354 : un focus et cinq masquages échouent à chaque passe, avec 110 échéances de stabilité et 16 passages de sécurité. La cause exacte du refus AX reste inconnue.

### Deux contrats de mémoire

- Garder `failedFrames` et son expiration historique de 30 s. Ses tests de compatibilité restent valides.
- Mémoriser séparément les placements directs refusés. La clé associe fenêtre/PID, bundle, scope, cible et cadre observé, liée à l’intention explicite. Une clé inchangée reste supprimée après 30 s ; aucun simple écho AX ne réarme l’écriture.
- Une nouvelle action réelle, géométrie externe, identité, configuration ou topologie permet une reprise. Une progression monotone différée vers la cible conserve le budget. Un geste confirmé puis traité libère ce budget ; un clic simple ne renouvelle ni génération ni budget. Supprimer les entrées devenues sans objet pour ne pas accumuler l’historique.
- Le contrôle agit par fenêtre. Aucun compteur global ni throttle des fenêtres saines.

### Stabilité

Pour toutes les commandes, armer la stabilité uniquement pour les cibles dont l’écriture a abouti. Sans succès, aucune nouvelle échéance. Une échéance passée ne doit pas entretenir une boucle. La correction borne les effets d’un refus ; elle ne prétend pas corriger la cause inconnue du refus d’accessibilité.

Accès attendu à la mémoire : O(1) par commande.

Preuves rouge → vert : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029RestorationRetryTests.swift couvre les 22 scénarios prévus, dont refus durable en modes libre et `spatialBsp`, tests au-delà de 30 s, reprise après changement réel, focus, stabilité et fenêtres saines. Worker retry prépare tests et patch temporaire ; seul le parent intègre dans la source partagée.
