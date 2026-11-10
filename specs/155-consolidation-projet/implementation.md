# Journal de réalisation — 155 consolidation

Reprise autorisée le 10 novembre 2026 à 15 h 36 CET, branche 155-consolidation-projet.
T001–T045 appliquées dans l'ordre, un seul exécuteur. Les commits intermédiaires des
anciennes recettes sont différés jusqu'aux gates de convergence/audit par my-specify-all.
Baseline 2523/383 ; paliers 2527/384, 2529/385, 2533/386, 2538/387, tous réussis.
Scripts : 28/28. Couverture 71,30 % lignes ; aucun gain de latence du produit revendiqué.
T046 : LICENSE exacte Apache-2.0 officielle et notices tiers dans les bundles.
T047 : tests Launcher écrits avant code ; échec attendu observé sur l'ancienne version.
T048 : TargetModeConfig, ConfigFileEditor et SettingsCollectionCodec réutilisés ; ADR 032.

## Self-review XIX/XX

Besoin : compatibilité des fichiers existants, priorité explicite et réinitialisation sûre.
Simplicité : aucun second modèle ni nouveau paquet ; alias public et édition par clé.
Hypothèses : les deux sections ont des types valides ; retour ancien binaire documenté.
Vérifications : diffs source relus, baseline/paliers complets, échec avant sur vrais parcours.
Non vérifié à ce stade : runtime installé, publication et tests complémentaires.
Code évité : migration de tous les consommateurs du modèle ; réencodage global TOML.
Complexité : O(nombre de clés) au décodage ; passages O(taille du fichier) en édition.

La suite complète a exposé un appel générique à ConfigFileEditor avec la clé fictive
`experimental.target_mode.rows`. L'alias a été limité aux clés connues du catalogue
existant : les clés inconnues gardent le comportement de l'éditeur générique. Le test
d'écriture SettingsService attend maintenant la forme canonique `[launcher]` prévue.

Le contrôle des vingt modifications conserve ses vingt assertions de valeurs et son
comparatif exact des lignes. Sa fixture utilise désormais `[launcher]`. La compatibilité
d'une écriture depuis l'ancienne forme est testée séparément par Spec155LauncherTests.

Observation réelle du test des vingt lignes : `# mode lettres` était déplacé sur sa propre
ligne parce que l'édition scalaire utilisait le moteur structuré. Correction ciblée :
l'alias réutilise le moteur scalaire pour les scalaires, qui garde le commentaire en fin
de ligne ; le moteur structuré reste réservé aux listes. Aucune assertion supprimée.
