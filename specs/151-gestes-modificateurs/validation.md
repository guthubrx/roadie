# Validation151 — en cours

Choix utilisateur : déplacementCtrl+gauche ; resizeCtrl+Alt+gauche. Deux réglages désactivables dans Tuilage. Synchronisation SpecKit par scripts officiels effectuée ; deux sauvegardes générées déplacées hors Git.
Tests ciblés :12puis15puis16tests verts après ajout des parcours du contrôleur et d’un relâchement perdu.35tests ciblés avec le catalogue verts en0,535s. Première suite complète :2477tests/375suites, trois assertions de décompte du catalogue échouées (308→310,228→230). Les assertions ont été mises à jour pour les deux nouveaux réglages ; seconde suite complète :2477tests/375suites verts en62,643s.
Le helper natif ne demande aucune autorisation. Son exécution JXA par l’action BTT existante vérifie AXIsProcessTrusted=true ; CGPreflightPostEventAccess n’est pas exposé par le pont JXA, ce n’est pas une preuve de refus. L’observation réelle des événements de la fenêtre fictive décidera si l’injection est utilisable. Aucun droit changé et aucun binaire de production arrêté à ce stade.
Le Python par défaut3.15 ne fournit pas Pillow et son extension Expat ne se charge pas. Les outils de preuve et plist utilisent /usr/bin/python3 déjà présent ; aucun environnement global réparé ou paquet installé.
Installation, revue de code et essais natifs : à faire. Aucune livraison anticipée.
