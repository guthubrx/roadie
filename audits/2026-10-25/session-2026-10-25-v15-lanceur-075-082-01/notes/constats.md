# Constats

## F1 MEDIUM - Demandes d'autorisation à la première ouverture de la barre (082)
`TargetModeRuntimeController.openItems` lit les onglets de chaque navigateur scriptable ouvert à
chaque ouverture de la barre, avant toute saisie. La première fois, macOS affiche une demande
d'automatisation par navigateur, sans lien visible avec un geste de l'utilisateur ; ensuite un
`osascript` par navigateur à chaque ouverture (2 s au plus, en fond). Recommandation : lire les
onglets à la première frappe, ou réglage d'activation. Décision de conception : non corrigé.

## F2 LOW - Écriture synchrone à chaque déplacement (081)
`LauncherMemoryStore.record` relit et réécrit le JSON (≤ 200 entrées) sur le fil principal à chaque
affectation de fenêtre. Déplacements rares (geste ou commande) ; coût borné. Recommandation : cache
mémoire et écriture différée si un jour mesurée.

## F3 LOW - Première fenêtre inconnue du paquet (077, 080)
`placeNewWindow` prend la première fenêtre nouvelle de l'application en 10 s : une fenêtre ouverte
par l'utilisateur dans ce délai serait rangée à la place (limite déjà notée en 074). Rouvrir un
projet attend jusqu'à 10 s par fenêtre qui ne vient pas.

## F4 LOW - Stage mémorisée pour des dossiers temporaires (077) - corrigé révision 1
`rememberFolder` enregistrait `folder:<dossier>` pour tout fichier ouvert, y compris `/tmp` :
4 entrées `folder:/tmp/roadie-07x` observées dans le classement réel (sauvegardé et nettoyé).
Code avant correction : `notes/avant-F4-rememberFolder.swift.txt`. Correction : même règle que la
recherche (`LauncherFileRules.isShown`), test ajouté (`Spec077FileRulesTests`).
