# Analyse par axe - diff 050 (commit 8c207d67, readonly)

## Sécurité
Lecture seule des préférences globales ; requête AX de rôle sous le pointeur, bornée à 0,5 s ; action
limitée à `toggle maximize` sur une fenêtre gérée. Aucun réseau, aucun secret.

## Logique et données
Garde à quatre conditions (double-clic, réglage, action macOS « None », bande de titre éligible), puis
exclusions (épinglée/flottante, rôle interactif). H1 réfuté par reproduction. F1 (défauts), F2 (doc).

## Concurrence
Moniteur global -> `DispatchQueue.main.async` -> traitement sur le fil principal, sérialisé avec la passe
du tiler. Interaction avec la session de geste vérifiée par reproduction isolée.

## Complexité et performance
Clic simple O(1). Double-clic (si macOS « Ne rien faire ») : un relevé complet + `hitTest` O(w) + une
requête AX ; conforme à R4, pré-filtre possible (même mécanisme que 051 F2).

## Tests
Six tests Spec050 sur les fonctions pures, le décodage et la santé ; `handleDoubleClick` non testé de bout
en bout malgré les injections (`readPreference`, `elementRoleAt`). La reproduction d'audit couvre
l'interaction avec le geste (hors dépôt). Pas de linter.

## Architecture
Deux injections ajoutées au contrôleur avec défauts ; réglage dans `TitlebarContextMenuConfig` ;
santé dépend de `effectiveConfig`. Aucune dépendance ni cycle ajoutés.

## Minimalisme et frugalité
Checklist : `MacOSWindowSetting` instancié à la volée pour le conflit double-clic (réutilise le format
du message, acceptable) ; aucune ligne supprimable à comportement constant identifiée ; aucune
dépendance ; aucun changement hors périmètre. Potentiel minimalisme : ~0 ligne (après examen ligne à ligne).

## Vertus LLM et responsabilité future
Contrainte macOS expliquée (moniteur sans consommation) ; revue 1 traitée (éléments interactifs, fenêtres
flottantes). Faiblesses : défaut `true` qui change la santé de la 049 sans le dire (F1), commentaire
déplacé (F2), validation non consignée (F3). Cet audit n'est pas indépendant.

## Observabilité
Événement `titlebar_context_menu.action` par double-clic traité, avec message de résultat. Aucun journal
pour un double-clic ignoré (normal, évite le bruit).
