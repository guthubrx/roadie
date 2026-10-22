# Validation 055

## Diagnostic et correction

Ancien plein écran Roadie : intent zoomReservesRail=false, mais le rail ne
considérait que le natif ou la taille avec une option. Taille seule utilisée
pour détecter une sortie : une fenêtre déjà grande n'entrait pas dans ce mode.
Quatre scénarios (1/2 fenêtres et taille initiale grande/petite) reproduisent
10 assertions échouées avant correction.

Intents des stages actives répartis en zoom avec/sans réserve. Le rail masque
seulement l'écran de la fenêtre visible de la bonne stage. Pas de nouvelle
lecture AX, timer ou configuration. Le survol ignore déjà les panneaux invisibles.
Le pin et auto_hide ne sont pas modifiés. La sortie se base sur l'intent explicite.

60 tests ciblés / 6 suites réussis : solo/multi, autre écran/stage, fenêtre
absente, application ajustant la taille, sortie et maximisation avec rail.
Aucun appel au writer fullscreen natif dans les scénarios.

## Masquage de type Dock et raccourci

Configuration réelle : fx.rail.auto_hide=true, hide_delay_ms=350.
État réel : isPinned=true ; le pin suspend le repli. Préserver cet état.
roadie rail unpin réactive le repli existant ; aucune nouvelle fonction à ajouter.
BTT : Ctrl gauche + Alt gauche + F libre au contrôle, keycode3, flags786432
et masques gauche786465. Action shell absolue vers la CLI installée.
Sauvegarde SQLite cohérente en lecture seule avant création via API AppleScript.

## Preuves visibles

CUA getState échoue encore : « CUA_REPL_ENABLED_SURFACES is required ».
Aucun geste aveugle, aucune nouvelle demande d'autorisation macOS.
Pas de capture après ni test de touche physique revendiqués à ce stade.

## Suite complète et revue

1 761 tests / 211 suites réussis après mise à jour d'un test historique qui
identifiait une sortie par la taille seule. En cas d'intent illisible, le test
garde ses assertions d'échec, absence d'écriture AX et absence de focus.

Revue en lecture seule, sans shell/diff/test ni écran côté réviseur :
- R1 : historique main vérifié par git log -S zoomReservesRail. Commit 6bf507f2
  introduit simultanément toggleMaximize et zoomReservesRail=true. Avant ce
  commit, seul toggleFullscreen enregistrait zoomedWindowID : nil est bien
  l'ancien plein écran, pas une ancienne maximisation avec rail.
- R2 : recalage du plein écran lors d'un changement de résolution non ajouté ici.
  C'est le comportement préexistant du placement ; essai de résolution non réalisé.
- R3 : si l'application accepte une taille contrainte, le mode demandé reste
  explicite et le rail reste caché. En cas de refus complet setFrame=nil, le
  chemin existant annule l'intent. Aucun masquage forcé après un refus total.
- R4 : maximize et fullscreen se remplacent sans perdre les cadres de retour ;
  comportement existant et tests de transition conservés.
- R5 : pas de nouveau champ ni format de persistance.
- R6 : rendu, survol et touche physique à confirmer faute de bureau accessible.
La revue confirme l'absence d'écriture du pin et l'exclusion des panneaux
invisibles dans le timer de survol. Aucun nouveau timer ni gain mesuré annoncé.

Contrôle CLI réel avant installation : rail status indique auto_hide=true,
edge_hit_width=8, edge_magnetism_width=28, hide_delay_ms=350 et runtime.pinned=true.
L'épinglage explique l'absence de repli constatée malgré l'option activée.

## Installation et raccourci vérifiés

Release compilée et installée, UUID E2CE37E8-CD10-3D53-978A-95F10F997E47 identique
entre la compilation et l'app installée. Codesign strict vérifié, certificat
78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration identique,
304 empreintes Sources/Tests inchangées entre suite complète et installation.
Redémarrage terminé, daemon PID17507, restore-watch PID17877, santé cinq contrôles OK.
La première requête santé est partie pendant l'ouverture du socket ; la seconde
a réussi après le démarrage complet, sans redémarrage supplémentaire.

Création via add_new_trigger dans le groupe BTT « 1 - Fenêtres », preset Francois.
UUID C9142EF4-3ACE-40DC-9CE4-74EF1811C60F. Relecture get_triggers : un seul raccourci
keycode3/modifiers786432, advanced786465, activé ; parent correct, action shell
vers /Users/moi/.local/bin/roadie toggle fullscreen. Les deux raccourcis existants
Option gauche+F et Option gauche+Maj gauche+F ne sont pas modifiés.
Karabiner inchangé, pin toujours true après redémarrage.

Essai utilisateur proposé pour les deux appuis et le survol. Non confirmé à ce
stade. Preuves visuelles incomplètes : accès CUA indisponible ; pas de capture
ou de geste physique automatisé revendiqué. Cette modification reste Non publié,
sans nouveau tag ni remplacement du DMG 0.6.0.
