# Validation de la session 043

## Périmètre livré
Poignées dans les espaces libres des séparations spatialBsp, réglage immédiat dans Tuilage, historique AX borné et priorité des intentions récentes lors d'un refus de taille. Les commandes et gestes natifs conservent leurs chemins existants. Aucun code Trellis n'est incorporé.

## Tests
1 685 tests Swift dans 199 suites réussis, compilation limitée à deux tâches. Les 26 tests de scripts passent. Aucun benchmark exécuté sur la machine chargée.

Les tests couvrent notamment deux et quatre fenêtres, coordonnées d'écran négatives, A→B→A, dernière cible de souris, persistance, fenêtres superposées, minimums, changement de génération/stage/configuration/topologie, relâchement, annulation, perte d'appui et retours AX désordonnés.

Deux tests existants dépendaient de l'horloge réelle. Une trace temporaire a montré un rejet avec un âge de 795 ms et tous les autres contrôles valides, au-delà de la limite de 150 ms. Les fixtures utilisent désormais une horloge contrôlée ; un test vérifie aussi le renouvellement du cache après 150 ms. La protection de production n'a pas été modifiée. La trace temporaire a été retirée.

Journaux et empreintes Sources/Tests conservés hors Git : /Users/moi/.roadies/diagnostics/2026-10-18-session043/.

## Revue indépendante T3
Trois livrables confiés à des agents distincts, puis deux passages de revue en lecture seule. Le premier a trouvé trois défauts d'intégration : retour A→B→A avec cadres anciens, fenêtre étrangère ignorée derrière la première fenêtre du scope et prise recouvrant une fenêtre à cause de la tolérance de position. Les trois défauts sont corrigés et couverts par des tests. Le second passage est favorable, sans nouveau finding bloquant.

Le minuteur de placement ne tourne que pendant le geste. Une seule cible est conservée ; le réglage désactivé évite les acquisitions de ce composant. Historique : au plus 32 cadres récents par fenêtre. Aucun gain de durée mesuré revendiqué.

## Preuves incomplètes
L'accès natif au bureau est indisponible : CUA renvoie `CUA_REPL_ENABLED_SURFACES is required` et screencapture renvoie `could not create image from display`. Aucun clic réel, aucune capture ni diaporama vérifié n'est revendiqué. Les tests AppKit et d'intégration ne remplacent pas les gestes réels. Restent à vérifier sur la version installée : glisser une poignée avec deux puis quatre fenêtres, relâcher, revenir au point de départ et désactiver/réactiver les poignées dans Tuilage.

## Livraison
Compilation Release réussie et installée le 18 octobre 2026. Les 292 empreintes Sources/Tests sont inchangées depuis la suite complète. UUID du daemon compilé et installé : C17A941A-2EAE-3084-BA67-E379185E9EA9. Signature stricte vérifiée ; certificat conservé : 78a75e8032f190a20072eb91cc2919aac344ef78.

Application : /Users/moi/Applications/Roadie.app. CLI : /Users/moi/.local/bin/roadie. Redémarrage confirmé, PID 89776. Quatre contrôles de santé OK, Accessibilité et configuration valides. Empreinte SHA-256 de la configuration personnelle inchangée : 301d7d43737c1deb31d2acaa3146ca5b285450a1bad65d27bd8cd095e19a3d77. Aucun changement de version ni nouvelle release publique.
