# Plan147 — après diagnostic
Diagnostic seul exécuté et quatre ouvertures CmdN corrélées aux décisions. Aucun retour à l’animation observé ; différence prouvée selon l’écran de naissance. Voir research.md.

Ajouter positionsBeforeResizing à ApplyCommand et WindowFrameUpdate (défautfalse, ancienJSON compatible). Marquer seulement les premières dispositions ; conserver le champ dans les lots intermédiaires et finaux. Le writer préfixe une tentative de position, puis conserve sizeBefore/position/sizeAfter. Un échec non fatal de la position anticipée laisse les phases historiques agir ; identité invalide, refus de génération ou quarantaine restent bloquants.

Tests rouge/vert : aucun resize avant destination quand le drapeau est demandé ; transit du drapeau dans le dispatcher, voisin connu inchangé ; voie sans animations, compatibilitéJSON, conservation position seule et révocation. Puis plusieurs créations avec naissance forcée naturellement à l’autre écran (replacer uniquement la fenêtre de test avant fermeture), série native et absence d’agrandissement à l’ancien emplacement. Aucun changement des profils/réglages utilisateur.
