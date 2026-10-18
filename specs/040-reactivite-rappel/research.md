# Diagnostic et réutilisation

Sources : /Users/moi/.roadies/diagnostics/2026-10-18-suivi/rapport.md et since-last-check.json ; échantillon /Users/moi/.roadies/diagnostics/2026-10-18-session040/sample-before.txt.

- recording_status : 3396 ms le 18 octobre à 09:21:24, dont 2979 ms de relevé. Aucun recording.json présent. RailController observe son dossier entier, également modifié par restore.json et les marqueurs d'activité.
- Les rappels du stage 2 à 09:44:18 et 09:44:21 ne trouvent aucune fenêtre ; StageCommands n'essaie qu'un membre avant d'activer l'application.
- Le focus AX ne retire pas AXMinimized. Les journaux montrent une réduction dans cette séquence ; tester le mécanisme sans prétendre reproduire le bureau réel.
- Neuf événements layout_apply contiennent quinze opérations échouées. Certaines fenêtres sont détruites pendant le relevé. Les sept external_change_reverted ne prouvent pas sept gestes utilisateur perdus.
- La capture écran échoue : could not create image from display. Aucun clic aveugle.

Harnais réutilisés : PowerUserProvider/Writer, RailTypographyTests, SpyAXFrameIO. Aucun cache durable supplémentaire.
