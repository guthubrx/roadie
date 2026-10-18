# Contrat : geste en attente (R1)

Sources : /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/FocusFollowsMouseController.swift (`UserInputActivity`) et /Users/moi/Nextcloud/10.Scripts/39.roadie/Sources/RoadieDaemon/LayoutMaintainer.swift.

## Invariants

- Une seule session en attente, non persistée. Un nouveau geste remplace l’ancienne session.
- `GestureSession.didDrag` est capturé pendant le cycle réel `mouseDown → mouseDragged → mouseUp`. Un simple clic ne déclenche ni polling ni mutation d’arbre et ne renouvelle ni génération ni budget d’écriture.
- La session garde l’identité fenêtre/PID et le scope au début de l’attente. Tout changement invalide le geste.
- Le geste ne doit pas être consommé uniquement parce que son scope est temporairement en garde ou suspendu.
- `UserInputActivity.blocksLayout` combine bouton physique pressé OU session souris encore ouverte. Le scheduler, le mainteneur et leurs tests utilisent cette même garde. La remontée de l’état physique avant le callback `mouseUp` ne suffit pas à reprendre immédiatement le tuilage. Le repli décrit ci-dessous couvre un callback perdu.

## Callback de relâchement perdu

La voie normale attend `mouseUp`. Si le bouton physique est relâché mais que la session reste ouverte, mémoriser le premier relâchement physique observé. Après un seuil de 300 ms depuis cette observation, `blocksLayout` clôture le geste une seule fois et laisse la passe le consommer.

- Tant qu’un bouton est réellement maintenu, aucun timeout ne clôture le geste.
- Un `mouseUp` tardif ne recrée ni ne rejoue le geste clôturé par le repli.
- Ce seuil de 300 ms est distinct de la fenêtre active de publication d’une taille.
- Le repli est consulté lors des événements ou par le filet périodique existant. Il n’ajoute pas de minuteur dédié et ne garantit pas une exécution à exactement 300 ms de temps réel.
- Tests rouge puis vert : callback perdu, bouton maintenu, consommation unique et `mouseUp` tardif. La baseline sans récupération produit 16 constats dans 20 tests d’une suite : /private/tmp/roadie-029-release-recovery-red-tests.log. La suite complète corrigée passe avec 1 526 tests dans 163 suites en 7,170 s : /private/tmp/roadie-029-release-recovery-full-tests.log.

## Bornes

Les lectures sont planifiées par pas de 50 ms, sans boucle serrée. La fenêtre de publication active dure au plus 300 ms quand le scope est traitable. La limite absolue est 2 s après le relâchement et couvre notamment les gardes existantes de 1,5 s. Les retries ne repoussent jamais cette limite. Ces valeurs sont des bornes choisies ; le retard réel de l’incident n’est pas mesuré.

| Situation | Résultat |
|---|---|
| Clic sans glissement | Aucune attente de publication. |
| Geste réel, scope sous garde | Conserver dans la borne absolue ; aucune réécriture contradictoire. |
| Scope traitable, taille finale pas encore publiée | Reprendre dans la fenêtre active, sans lecture bloquante. |
| Taille valide disponible | Appliquer une fois l’ajustement de frontière, supprimer l’attente et libérer le budget du geste confirmé. |
| Nouveau geste | Remplacer la session précédente. |
| Fenêtre/PID/scope changé, dépôt reconnu ou plein écran incompatible | Abandonner. |
| Limite atteinte | Abandonner et retirer l’échéance ; aucun retry résiduel. |

Les minima réels et les refus d’ajustement restent applicables. Un bord extérieur ne crée pas de disposition libre. Le focus, les dépôts et la gestion des échos AX restent protégés.

## Preuves attendues

/Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029ResizeTests.swift reproduit en rouge puis en vert : publication tardive et consommation sous garde. Les tests protègent aussi clic simple, remplacement, identité/scope, expiration et refus existants, avec doubles locaux sans permission AX réelle.

## Poignées et obstacles

Le picker respecte l’ordre Z réel des fenêtres. Une poignée reste éligible si sa fenêtre est devant le premier intérieur inéligible. Un intérieur inéligible au premier plan bloque les fenêtres derrière lui. Cela évite qu’une bordure décorative placée derrière son parent fasse perdre la poignée. Le choix strict du focus ne change pas.

Les tests de masquage visent l’intérieur de l’obstacle : le point antérieur à `maxY` était exclu du rectangle. Les nouvelles fixtures emploient notamment y = -350 plutôt que -300 et les écarts réels de 0,836 et 4,188 points du cadre.

## Preuves de la reprise

- /private/tmp/roadie-029-release-race-red-tests.log : un test rouge, six constats sur le tick AX avant le callback de relâchement. Le même cas passe dans /private/tmp/roadie-029-release-race-green-tests.log.
- /private/tmp/roadie-029-picker-red-tests.log : huit tests, quatre constats sur les poignées et obstacles. Suite : /Users/moi/Nextcloud/10.Scripts/39.roadie/Tests/RoadieDaemonTests/Spec029PickerOcclusionTests.swift.
- Deux tests supplémentaires de `Spec029ResizeTests` couvrent la course et l’absence de session.

Le diagnostic `window_gesture_target` expose le premier intérieur, l’application, le scope et le statut de candidat ; aucun titre de fenêtre n’est ajouté.

Mémoire du geste O(1). Aucun changement de `LayoutTolerance`. Les premières reproductions n’identifiaient pas le geste exact de l’incident ; les événements de la reprise établissent désormais une course précise avant `mouseUp`. La réinstallation est terminée ; le résultat natif reste à confirmer par le nouvel essai utilisateur.
