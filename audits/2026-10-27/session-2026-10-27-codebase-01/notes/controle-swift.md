# Analyse statique Swift et complexité

SwiftLint installé a examiné les fichiers Swift de `Sources` avec cinq règles ciblées : conversions forcées, déballages forcés, `try!`, délégués faibles et observateurs de notification. Il a signalé 33 occurrences ; son code de sortie 2 correspond aux alertes de conversions forcées, pas à une compilation. Les règles de style ne constituent pas une recherche exhaustive de défauts.

Les contextes des occurrences ont été lus ; les gardes et les appelants de plusieurs d'entre elles ont été vérifiés. Les déballages sur les tableaux de composants issus de `components(separatedBy:)`, les valeurs déjà filtrées, les cas `switch` et les candidats de restauration ont une protection locale. Les conversions AXValue utilisées par `readFrame` et par `SystemSnapshotProvider` suivent une vérification de type Core Foundation. La valeur du cache JSON est capturée avant la vérification de signature et son type est contrôlé. Des limites demeurent pour les cas d'exécution, les appelants non suivis et les autres règles non testées.

Une première recherche limitée à `copyFrame(` a manqué la référence de fonction `Self.copyFrame` : la compilation a échoué après suppression. La fonction a été rétablie. Potentiel minimalisme du dépôt : non mesuré ; aucune suppression de cette fonction n'est revendiquée.

Une conversion non vérifiée de valeur AX a été testée dans un sous-processus avec une chaîne synthétique. L'appel `AXUIElementGetPid` a renvoyé l'erreur -25202 sans arrêt : ce témoin ne confirme pas un crash. Il ne prouve pas que tous les types AX inattendus sont sûrs.

Le classement du lanceur additionnait des compteurs `Int` issus d'un fichier JSON. Avec un compteur `Int.max`, l'incrément et la somme par préfixe arrêtaient chacun un sous-processus sur une copie de la logique initiale. La correction sature à `Int.max` et les tests vérifient les deux variantes. Les tailles normales restent inchangées. La profondeur récursive de la calculatrice est aussi bornée ; aucune amélioration de vitesse n'est revendiquée sans mesure.
