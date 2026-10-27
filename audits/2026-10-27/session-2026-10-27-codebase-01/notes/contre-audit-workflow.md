# Contre-audit indépendant — identifiant de workflow

Mission Bridget `55358f72-c669-4e64-9d83-a46ff14b2a76`, demande `roadie-093-counteraudit-workflow-path-20261027-v1`, relecteur `f79eb405-f9b6-4172-9e83-3f2d0fad9fb3`, rendu le 27 octobre 2026.

Verdict de la revue indépendante : défaut confirmé par lecture du code, impact élevé. Un `bundleid` égal à `..` est conservé par le chargeur et cible le parent de `workflows` lors d'une installation avec `--replace`. Le nom `.` cible le dossier des workflows. La suppression accepte aussi ces noms si le dossier visé contient un `info.plist`. Le remplacement des barres obliques ne protège pas ces composants.

La revue a tenté de reproduire le cas, mais son espace de travail distant était en lecture seule. Elle n'a pas pu accéder au témoin local ni effectuer le test macOS. La preuve d'exécution locale est donc distincte : `notes/repro-workflow-path.swift` et la sortie de la commande enregistrée dans `runs/20261027T051758802868Z/`. Cette sortie montre la suppression d'une sentinelle synthétique sous un dossier temporaire de la session.

Mesure proposée : refuser les composants réservés avant toute suppression. La revue suggère aussi de restreindre les caractères autorisés ; cela n'a pas été retenu sans preuve que les identifiants déjà valides doivent être interdits. La comparaison de chemin et les liens symboliques restent des points distincts à qualifier.
