# Variantes : index des littéraux et parcours quadratiques

## Valeur vide non notée (F-LITERAL-EMPTY)

Recherche de la même cause : test différentiel à graine fixe sur le vrai code (`repro-audit129.swift`).
Générateur de 29 formes de lignes (tables, tables répétées, `[[arr]]`, `[ a ]`, clés pointées, clés
citées, tables en ligne, listes et chaînes sur plusieurs lignes, chaînes ouvertes, commentaires,
valeurs vides) ; 5 tables × 5 clés sondées par fichier.
- Run `20261029T181537082575Z` : 3 000 fichiers ; écarts présents, les 8 gardés ont tous une ligne `y =`.
- Run `20261029T181646448678Z` : 5 000 fichiers sans `y =` mais avec `y = # vide` : 71 écarts, tous dans
  un fichier qui contient `y = # vide` ; 0 autre écart.
Conclusion : une seule cause (valeur vide ou réduite à un commentaire, ligne 132 de ConfigFileEditor).
Limite : le générateur ne couvre pas les clés Unicode, les échappements de chaînes littérales multiples
ni les fichiers de plus de 14 lignes.

## Retrait en tête de tableau dans une boucle (F-FIREFOX-BFS)

Commande : `grep -rn "removeFirst()" Sources`. 9 résultats lus.
- `LauncherOpenItems.swift:160` (FirefoxTabSelector) : `Array`, dans une boucle bornée à 4 000 : variante retenue.
- `LauncherCalculator.swift:108-129` : `ArraySlice` (`Array(text)[...]`), retrait O(1) : témoin protégé.
- `Config.swift:747`, `NSColorHex.swift:8` : un seul retrait, hors boucle : sans objet.
Recherche complémentaire `queue.removeFirst\|removeFirst(` dans les parcours AX (AppTargetQueryService,
SystemSnapshotProvider) : aucun autre parcours en largeur de cette forme.
