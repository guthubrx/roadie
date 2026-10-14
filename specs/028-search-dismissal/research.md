# Diagnostic — session 028

## Données observées

La capture utilisateur montre Drafts dans la barre latérale Outlook et « draft »
avec zéro résultat. Le modèle de recherche utilise une sous-chaîne normalisée :
le pluriel ne justifie donc pas ce résultat si le libellé a été collecté.

Le journal du daemon contient des scans Outlook incomplets : le 14 octobre 2026
à 06:31:48 UTC, 452 éléments parcourus, 128 candidats, 255 hors écran, arrêt après
2003 ms. Des scans précédents complets parcouraient 806 éléments en 1511–1741 ms.
Ces mesures prouvent une collecte parfois incomplète, pas l’identité du contrôle
Drafts dans l’arbre. Le scanner associe les textes enfants aux cibles uniquement
dans les zones web ; une ligne native sans titre propre peut perdre son libellé.

Le tap clavier ne surveille pas les clics. Les panneaux couvrent chaque écran et
ignorent la souris : la perte de focus de fenêtre ne suffit pas. SearchBarLayout
connaît les véritables rectangles de la barre et du panneau de commandes.

## Limites d’observation

CUA est indisponible (`CUA_REPL_ENABLED_SURFACES is required`). La commande locale
de lecture des cibles renvoie `accessibility_denied`. Le daemon installé est
autorisé et produit les scans cités. Des fixtures natives et un essai manuel
après installation compléteront ces observations sans changer les permissions.
