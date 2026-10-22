# Session 055 - Plein écran Roadie sans rail

Demande explicite : Ctrl gauche + Alt gauche + F remplit la zone utile sans
plein écran macOS et cache le rail même au survol. Répéter restaure.
Intent fullscreen existant réutilisé : masquage limité à la stage active et
à son écran, indépendant du pin et de hide_on_maximized. Une fenêtre déjà
grande entre aussi dans le mode explicite. Maximisation avec rail conservée.

Mode Dock déjà disponible : auto_hide=true, mais pin utilisateur=true ; conserver
ce dernier. Commande rail unpin documentée pour réactiver le repli.

10 assertions échouent avant correction, 60 tests ciblés passent puis
1 761 tests / 211 suites réussissent. Revue indépendante traitée et historique
de zoomReservesRail contrôlé. Docs FR/EN et changelog Non publié actualisés.
UUID E2CE37E8-CD10-3D53-978A-95F10F997E47, PID17507, santé 5/5.
Configuration/certificat conservés. Raccourci BTT créé et relu, UUID
C9142EF4-3ACE-40DC-9CE4-74EF1811C60F, flags786465 pour les deux modificateurs gauche.
Reçu : specs/055-fullscreen-sans-rail/validation.md.
Preuves visuelles incomplètes : CUA inaccessible, essai utilisateur proposé.

Code b92dc331 fusionné/poussé ; branche supprimée. Recette temporaire et build
nettoyés ; worktree actif conservé détaché, diagnostics et sauvegarde BTT hors Git.

Complément du 23 octobre : action BTT corrigée par API après reproduction du
chemin shell invalide. Script brut distinct de Config ; masques et groupe
conservés. Deux bascules BTT réussies, santé 5/5, utilisateur « ca marche ».
Aucun changement Sources/Tests ni nouvelle installation.
