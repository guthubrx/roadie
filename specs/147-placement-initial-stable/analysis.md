# Cohérence147 et revue locale

FR1 : le premier placement transmet positionsBeforeResizing au writer, avec et sans propriétaire d'animation. Une tentative de position précède le trio historique. Le test rouge reproduit l'agrandissement à l'origine ; les tests verts vérifient destination, budget et transit.

FR2 : les fenêtres connues gardent le drapeau faux et leur interpolation. Le test commun observe réellement des cibles intermédiaires pour la voisine, et seulement la cible finale pour la nouvelle fenêtre.

FR3 : quatre CmdN avant correction ont tous reçu la politique directe ; un cas a grandi avant son déplacement entre écrans. L'hypothèse d'une reprise animée n'est pas confirmée. Les essais natifs après installation sont consignés séparément, avec leurs limites.

FR4 : aucun changement de configuration, permissions, profil iTerm ou magasin global. Les gardes de génération/quarantaine et l'invalidation d'identité encadrent chaque attribut. Le nouveau préfixe reste dans la même tentative de cadre ; il n'ajoute aucun minuteur, relecture AX ni budget. preservesSize prime et ne fait qu'une position. Ancien JSON compatible.

Complexité : phase AX bornée, O(1) par fenêtre, un attribut supplémentaire au premier placement. La propagation reste O(n). Le diagnostic par lot utilise un tri des IDs directs, O(k log k), et des chaînes de cadres O(n), sans titre ni contenu. Pas de diagnostic à chaque image d'animation.

Tests : deux tests rouges avant implémentation ; 47 tests ciblés verts, puis 2431 tests dans 364 suites et 28 tests de scripts réussis. Aucun échec de suite ignoré.

Revue indépendante : demande Bridget 64107f38-d4bf-4330-a53b-9e5c16283761, base5f0e6182b0431b1afb0362be308bf3e5ad1c6905, dossier partagé, lecture seule. Refus routing_candidate_unavailable ; 18 candidats capability_unavailable, 11 workspace_diverged, sous-cause unobserved. Admission not_recorded, aucune tâche créée. La base locale est bien celle demandée ; aucune modification d'un dossier distant ni changement d'hôte pour contourner le refus. Cette relecture locale ne vaut pas revue indépendante. Aucun grade d'audit V15 revendiqué.

Une série avantcross a été invalidée par un changement de stage pendant la mesure ; elle n'est pas comptée comme résultat de placement. L'ancrage antérieur avait aussi expiré : aucun ancien ID n'a été recréé comme fenêtre utilisateur.
