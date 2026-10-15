# Modèle de données : session 029

## Session de geste en mémoire

Une seule session en attente dans `LayoutMaintainer`. Aucun dictionnaire de gestes ni persistance.

| Donnée | Invariant |
|---|---|
| Session d’entrée | Fenêtre, cadre de départ, début et relâchement ; `didDrag` provient d’un vrai événement de glissement. |
| Identité capturée | Identifiant de fenêtre, PID et scope. Un changement invalide l’attente. |
| Échéances | Fenêtre active maximale de 300 ms ; lectures planifiées par pas de 50 ms ; limite absolue de 2 s depuis le relâchement. |

Un nouveau geste remplace l’attente. Les reprises ne repoussent jamais la limite absolue. Un clic simple ne crée aucune attente de publication.

## Origine persistante

Structure existante `StageOrigin`, dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StageStore.swift.

- `position`, identités d’écran/bureau/stage et `nameAtParking` restent la source de vérité.
- Seul ajout prévu : `modeAtParking`, optionnel, pour reconnaître un placeholder intact. Les anciens fichiers restent lisibles sans migration massive.
- Aucun champ `orderedStageIDs`. L’ordre courant du tableau garde les modifications de l’utilisateur.
- Le placeholder reste tant qu’une copie avec origine correspondante existe. La matérialisation conserve l’origine nécessaire au retour ultérieur.
- Une copie sans origine ou explicitement native ne doit pas être rattachée de force.

## Projection calculée du rail

`StagePresentationOrder`, dans /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/StagePresentationOrder.swift, est calculé depuis le scope, les membres vivants et l’instant.

Ses entrées associent identifiant brut, position visible et nom. Elles incluent les membres vivants, ceux sous grâce de 15 s et les stages vides nommés. L’opacité ne participe pas au calcul. Les vides automatiques restent un repli d’affectation après les entrées visibles. Aucun état dérivé n’est persisté.

## Refus d’écriture en mémoire

Deux mémoires ont des contrats différents :

1. La mémoire historique `failedFrames` conserve son expiration de 30 s et ses tests existants.
2. La mémoire des placements directs refusés conserve une clé fenêtre/PID, bundle, scope, cible et cadre observé, liée à l’intention explicite. Une clé inchangée reste supprimée au-delà de 30 s. Une vraie action, géométrie, identité, configuration ou topologie nouvelle autorise une reprise. Un simple écho AX ne suffit pas.

Les fenêtres disparues et intentions remplacées doivent libérer leurs entrées. La stabilité contient uniquement les cibles dont l’écriture a abouti ; aucun échec ne crée de nouvelle échéance.

## Complexité attendue

| Opération | Coût |
|---|---|
| Stocker ou remplacer le geste | O(1) |
| Construire la projection du rail | O(s + m), s stages et m membres |
| Reconnaître un refus | O(1) par commande |
| Remplacer un placeholder déjà localisé | O(1) |
| Chercher puis insérer dans le tableau de stages | O(s) |

Aucun historique global d’ordre, compteur global de retries ou nouvelle dépendance.
