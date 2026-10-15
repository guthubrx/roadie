# Contrat : retour d’écran (R3) et reprises bornées (R4)

## Retour d’écran

Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/DisplayParkingService.swift et structure `StageOrigin` dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageStore.swift.

1. Utiliser `StageOrigin.position`, déjà persistant. Ne pas ajouter `orderedStageIDs`.
2. Si le placeholder d’origine est intact, le remplacer à sa place actuelle. Cela conserve l’ordre choisi par l’utilisateur pendant l’absence.
3. Si le placeholder est absent, insérer avec la position d’origine bornée aux limites du tableau.
4. Conserver les renommages et changements de mode faits pendant l’absence. Un champ optionnel `modeAtParking` permet de distinguer le mode initial du mode modifié ; les anciens fichiers restent lisibles.
5. Garder le placeholder tant qu’une copie correspondante existe. La matérialisation après 60 s conserve la place du stage dans le scope hôte et l’origine nécessaire au retour ultérieur.
6. Au retour d’écran, traiter aussi une copie `.restored` si son origine existe encore et si son scope physique ou logique diffère du scope d’origine. Le retour reste possible après une nuit.
7. Respecter une copie sans origine ou explicitement détachée avec `.native`. Ne pas fusionner de membres ni écraser une modification utilisateur.
8. Corriger le diagnostic d’origine absente vide localement, sans nouveau format général d’événements.

Les recherches et insertions dans les tableaux restent O(s), s étant le nombre de stages du scope. Aucun état global d’ordre supplémentaire.

Preuves rouge → vert : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029DisplayParkingTests.swift couvre retour court, après matérialisation et après une nuit, placeholder réordonné ou absent, noms/modes modifiés, anciens fichiers, copie détachée et idempotence.

## Reprises après refus

Source : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift. Intégration par le parent après gel du lot gestes.

### Constat

Les placements hors arbre ne sont pas tous mémorisés lors d’un refus. Un chemin de focus contourne aussi le budget d’écriture d’arbre. La stabilité peut être réarmée par des écritures échouées. Le diagnostic compte 128 passes en 33,577 s pour la même génération 354 : un focus et cinq masquages échouent à chaque passe, avec 110 échéances de stabilité et 16 passages de sécurité. La cause exacte du refus AX reste inconnue.

### Deux contrats de mémoire

- Garder `failedFrames` et son expiration historique de 30 s. Ses tests de compatibilité restent valides.
- Mémoriser séparément les placements directs refusés. La clé associe fenêtre/PID, bundle, scope, cible et cadre observé, liée à l’intention explicite. Une clé inchangée reste supprimée après 30 s ; aucun simple écho AX ne réarme l’écriture.
- Une nouvelle action réelle, géométrie, identité, configuration ou topologie permet une reprise. Supprimer les entrées devenues sans objet pour ne pas accumuler l’historique.
- Le contrôle agit par fenêtre. Aucun compteur global ni throttle des fenêtres saines.

### Stabilité

Armer la stabilité uniquement pour les cibles dont l’écriture a abouti. Sans succès, aucune nouvelle échéance. Une échéance passée ne doit pas entretenir une boucle. La correction borne les effets d’un refus ; elle ne prétend pas corriger la cause inconnue du refus d’accessibilité.

Accès attendu à la mémoire : O(1) par commande.

Preuves rouge → vert : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029RestorationRetryTests.swift couvre les 20 scénarios prévus, dont refus durable en modes libre et `spatialBsp`, tests au-delà de 30 s, reprise après changement réel, focus, stabilité et fenêtres saines. Worker retry prépare tests et patch temporaire ; seul le parent intègre dans la source partagée.
