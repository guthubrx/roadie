# Contrat : geste en attente (R1)

Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/FocusFollowsMouseController.swift (`UserInputActivity`) et /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Sources/RoadieDaemon/LayoutMaintainer.swift.

## Invariants

- Une seule session en attente, non persistée. Un nouveau geste remplace l’ancienne session.
- `GestureSession.didDrag` est capturé pendant le cycle réel `mouseDown → mouseDragged → mouseUp`. Un simple clic ne déclenche ni polling ni mutation d’arbre.
- La session garde l’identité fenêtre/PID et le scope au début de l’attente. Tout changement invalide le geste.
- Le geste ne doit pas être consommé uniquement parce que son scope est temporairement en garde ou suspendu.

## Bornes

Les lectures sont planifiées par pas de 50 ms, sans boucle serrée. La fenêtre de publication active dure au plus 300 ms quand le scope est traitable. La limite absolue est 2 s après le relâchement et couvre notamment les gardes existantes de 1,5 s. Les retries ne repoussent jamais cette limite. Ces valeurs sont des bornes choisies ; le retard réel de l’incident n’est pas mesuré.

| Situation | Résultat |
|---|---|
| Clic sans glissement | Aucune attente de publication. |
| Geste réel, scope sous garde | Conserver dans la borne absolue ; aucune réécriture contradictoire. |
| Scope traitable, taille finale pas encore publiée | Reprendre dans la fenêtre active, sans lecture bloquante. |
| Taille valide disponible | Appliquer une fois l’ajustement de frontière, puis supprimer l’attente. |
| Nouveau geste | Remplacer la session précédente. |
| Fenêtre/PID/scope changé, dépôt reconnu ou plein écran incompatible | Abandonner. |
| Limite atteinte | Abandonner et retirer l’échéance ; aucun retry résiduel. |

Les minima réels et les refus d’ajustement restent applicables. Un bord extérieur ne crée pas de disposition libre. Le focus, les dépôts et la gestion des échos AX restent protégés.

## Preuves attendues

/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability/Tests/RoadieDaemonTests/Spec029ResizeTests.swift reproduit en rouge puis en vert : publication tardive et consommation sous garde. Les tests protègent aussi clic simple, remplacement, identité/scope, expiration et refus existants, avec doubles locaux sans permission AX réelle.

Mémoire O(1). Aucun changement de `LayoutTolerance` ni du scheduler prévu. Les tests reproduisent des défauts du code ; ils n’identifient pas le geste exact de l’incident utilisateur.
