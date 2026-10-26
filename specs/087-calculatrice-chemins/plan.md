# Plan 087

| Zone | Fichier | Changement |
|---|---|---|
| Calcul | `Sources/RoadieDaemon/LauncherCalculator.swift` (nouveau) | analyseur à descente récursive, fonctions, mise en forme selon la langue |
| Chemin | `Sources/RoadieDaemon/LauncherPath.swift` (nouveau) | règle chemin/commande, découpage dossier + suite, complétion, lecture d'un dossier hors fil principal |
| Liste | `Sources/RoadieDaemon/LauncherList.swift` | `Row.calc`, liste « Chemin » faite de lignes `.file` (077) |
| Barre | `Sources/RoadieDaemon/TargetOverlayPresenter.swift` | aiguillage `/` (commande ou chemin), lecture du dossier, ligne Calcul en tête, Tab complète, Retour/⌘C copient le résultat |

Complexité : calcul O(n) caractères ; chemin O(e) éléments lus (≤ 5 000 parcourus, 200 gardés),
tri O(k log k) des gardés ; règle `/` O(c + r) commandes et éléments de `/` (en mémoire).
Réutilisé : `LauncherFile` et tout son parcours (Retour, verbes, ⌘C, ⌘Y, variantes), `LauncherMatch`,
`SlashCommandCatalog.commands`, `prepend` de la liste (phrase 079).
Tests : `Tests/RoadieDaemonTests/Spec087CalculatorTests.swift`, `Spec087PathTests.swift`.
Article XX : deux fichiers neufs à responsabilité unique ; aucun état dérivé gardé hors de la session.
