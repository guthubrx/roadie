# Modèle de données : session 029

> Document historique récupéré le 18 octobre 2026. Les statuts, chemins de travail et résultats ci-dessous décrivent le travail de l'époque. Voir [consolidation.md](consolidation.md) pour l'état actuel et les évolutions qui remplacent certaines décisions.

## Session de geste en mémoire

Une seule session en attente dans `LayoutMaintainer`. Aucun dictionnaire de gestes ni persistance.

| Donnée | Invariant |
|---|---|
| Session d’entrée | Fenêtre, cadre de départ, début et relâchement ; `didDrag` provient d’un vrai événement de glissement. |
| Identité capturée | Identifiant de fenêtre, PID et scope. Un changement invalide l’attente. |
| Échéances | Fenêtre active maximale de 300 ms ; lectures planifiées par pas de 50 ms ; limite absolue de 2 s depuis le relâchement. |

Un nouveau geste remplace l’attente. Les reprises ne repoussent jamais la limite absolue. Un clic simple ne crée aucune attente de publication et ne renouvelle ni génération ni budget d’écriture.

## Garde d’entrée partagée

`UserInputActivity.blocksLayout` est une valeur calculée : bouton physique pressé OU session de souris encore ouverte. Le scheduler, le mainteneur et le harnais emploient la même condition. Aucun nouvel état persistant. Un callback `mouseUp` encore en attente conserve donc la garde même si le bouton physique est déjà relâché. Un marqueur en mémoire retient le premier relâchement physique observé. Après un seuil de 300 ms sans callback, le repli clôture le geste une seule fois et laisse la passe le consommer. Aucun timeout pendant un maintien physique ; un callback tardif ne rejoue pas le geste. Le seuil est consulté par les événements ou le filet périodique existant, sans promesse d’exécution à exactement 300 ms.

## Origine persistante

Structure existante `StageOrigin`, dans /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StageStore.swift.

- `position`, identités d’écran/bureau/stage et `nameAtParking` restent la source de vérité. Aucun nouveau champ, aucune migration de schéma.
- Aucun tableau d’ordre redondant. L’ordre courant du scope garde les modifications de l’utilisateur.
- Le placeholder `.parked` correspondant reste le témoin d’un retour encore attendu après matérialisation. Une copie `.restored` est éligible seulement si ce témoin existe dans le bureau/écran d’origine, reconnu par identité physique ou logique.
- Sans placeholder, une ancienne copie `.restored` reste sur son écran actuel. Les copies encore `.parked` conservent le repli historique sur la position.
- Un déplacement explicite vers un écran détache le stage : `.native`, puis `origin`, `host` et `restoredAt` à `nil`. Une copie sans origine ou native ne doit pas être rattachée de force.
- Un ancien placeholder dont le mode d’origine est inconnu reste conservé par prudence. Capturer le caractère automatique du nom avant détachement ; réécrire seulement un nom automatique après choix de l’identifiant final. Un nom personnel reste inchangé. Une destination vide nommée, de mode différent ou avec arbre explicite garde son identité et sa structure ; le transfert alloue un autre identifiant.

## Projection calculée du rail

`StagePresentationOrder`, dans /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/StagePresentationOrder.swift, est calculé depuis le scope, les membres vivants et l’instant.

Ses entrées associent identifiant brut, position visible et nom. Elles incluent les membres vivants, ceux sous grâce de 15 s et les stages vides nommés. L’opacité ne participe pas au calcul. Les vides automatiques restent un repli d’affectation après les entrées visibles. Aucun état dérivé n’est persisté.

## Refus d’écriture en mémoire

Deux mémoires ont des contrats différents :

1. La mémoire historique `failedFrames` conserve son expiration de 30 s et ses tests existants.
2. La mémoire des placements directs refusés conserve une clé fenêtre/PID, bundle, scope, cible et cadre observé, liée à l’intention explicite. Une clé inchangée reste supprimée au-delà de 30 s. Une vraie action, géométrie externe, identité, configuration ou topologie nouvelle autorise une reprise. Une progression monotone différée vers la cible conserve le budget. Un geste confirmé puis traité le libère ; un clic simple ne le renouvelle pas. Un simple écho AX ne suffit pas.

Les fenêtres disparues et intentions remplacées doivent libérer leurs entrées. Pour toutes les commandes, la stabilité contient uniquement les cibles dont l’écriture a abouti ; aucun échec ne crée de nouvelle échéance.

## Complexité attendue

| Opération | Coût |
|---|---|
| Stocker ou remplacer le geste | O(1) |
| Construire la projection du rail | O(s + m), s stages et m membres |
| Reconnaître un refus | O(1) par commande |
| Remplacer un placeholder déjà localisé | O(1) |
| Chercher puis insérer dans le tableau de stages | O(s) |

Aucun historique global d’ordre, compteur global de retries ou nouvelle dépendance.
