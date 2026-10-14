# Plan — session 026

Réutiliser les modèles de recherche et de commandes ainsi que le décodage clavier.
La recherche distingue Tab des autres touches de navigation. La complétion respecte
la sélection et conserve l'identité de la cible après recalcul des résultats.

Extraire le rendu de la barre dans un composant AppKit interne, sans nouvelle fenêtre.
Le calcul de géométrie utilise l'écran et les tailles de police ; le contenu textuel
ne détermine plus la largeur. La pastille dispose de son propre cadre à droite.
Le composant extrait sert aussi au rendu hors écran, sans exposer la vue des badges.

Fichiers principaux : TargetSearchModel.swift, SlashCommandModel.swift,
TargetOverlayPresenter.swift, SearchBarRenderer.swift, tests Swift existants
et nouveaux tests de la session 026. Les badges de cible gardent leur style actuel.

Ordre : tests de régression, modèles et routage, extraction et rendu,
tests ciblés, revue indépendante autorisée, suite complète et installation,
validation utilisateur, documentation, commits et fusion.

Risques : confusion entre Tab et navigation, troncature des grandes polices,
compteur débordant sur très petit écran. Vérifier ces frontières sans modifier
la configuration réelle de l'utilisateur pour les rendus de validation.
