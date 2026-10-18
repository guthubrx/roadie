# Diagnostic et réutilisation

Sources : /Users/moi/.roadies/diagnostics/2026-10-18-suivi/rapport.md et since-last-check.json ; échantillon /Users/moi/.roadies/diagnostics/2026-10-18-session040/sample-before.txt.

- recording_status : 3396 ms le 18 octobre à 09:21:24, dont 2979 ms de relevé. Aucun recording.json présent. RailController observe son dossier entier, également modifié par restore.json et les marqueurs d'activité.
- Les rappels du stage 2 à 09:44:18 et 09:44:21 ne trouvent aucune fenêtre ; StageCommands n'essaie qu'un membre avant d'activer l'application.
- Le focus AX ne retire pas AXMinimized. Les journaux montrent une réduction dans cette séquence ; tester le mécanisme sans prétendre reproduire le bureau réel.
- Neuf événements layout_apply contiennent quinze opérations échouées. Certaines fenêtres sont détruites pendant le relevé. Les sept external_change_reverted ne prouvent pas sept gestes utilisateur perdus.
- La capture écran échoue : could not create image from display. Aucun clic aveugle.

Harnais réutilisés : PowerUserProvider/Writer, RailTypographyTests, SpyAXFrameIO. Aucun cache durable supplémentaire.

## Vérifications et décisions

- Tests avant correction : sept assertions échouent pour le watcher et les deux chemins de rappel ; deux pour le focus réduit. Après correction : 70 tests ciblés réussis.
- Le journal détaillé omettait les échecs des commandes directes de masquage. Un test de masquage refusé reproduit l'absence de layout_failed. La correction conserve les compteurs et ajoute l'identité manquante.
- Revue indépendante : garder le watcher du dossier avec signature du fichier, préserver plein écran, exclure les fermetures confirmées. Ces points sont intégrés. Les tentatives sont bornées aux membres éligibles, une fois chacun, avec arrêt au premier succès. Un plafond arbitraire de trois candidats aurait laissé une quatrième fenêtre valide définitivement inaccessible.
- Les trois restore.unhide_all_failed ont des failed_window_ids dans leur payload : 189726 (Chrome) deux fois, cadre encore caché, puis 124 au démarrage. La synthèse précédente avait omis ces détails. Chrome est ensuite restauré à 06:42:54 ; aucune boucle sans borne établie.
- Les échecs de placement liés à AXUIElementDestroyed disparaissent avec la fenêtre. Les autres erreurs n'ont pas de diagnostic AX détaillé suffisant. Aucun changement spéculatif des coordonnées ou du délai AX.
- CUA indisponible : CUA_REPL_ENABLED_SURFACES is required. Capture native indisponible. Les tests AX utilisent un PID fictif, aucune fenêtre utilisateur n'est activée.
