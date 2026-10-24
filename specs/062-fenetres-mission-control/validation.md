# Validation 062 - Fenêtres rétrécies par Mission Control

Date : 2026-10-24. Branche : `session-062-fenetres-mission-control` (depuis 061, commit 2f17523c).

## Diagnostic (avant correction)
- Repos : T3 Code 1837×2114, Thunderbird et iTerm2 3690×2122 (masquées, x = 5351).
- Mission Control ouvert : T3 Code 575×662 en x = 3101, Thunderbird 1155×664 en x = 1532.
- Après fermeture : T3 Code revenu à 1837×2114 ; Thunderbird et iTerm2 restées à 1155×664.
- Journal du 24 octobre 12 h 40 et 13 h 13 : `layout_app_response_accepted` avec 449×257, 449×516, 575×662.
- restore.json : Thunderbird 715×411 et iTerm2 715×411 en position visible ; arrêt de Roadie (`restore.unhide_all`) les réapplique.
- Événement iTerm2 12 h 01 : `ax.sizeBefore = -25204`, relecture absente, frame acceptée en 276×158.
- Signature : fenêtres du Dock de niveau 18 et 20 couvrant chaque écran, absentes hors Mission Control.

## Tests
- 7 tests SPEC-062 (sonde, écriture position seule, masquage lors d’un changement de stage, pause de la passe,
  relevé provisoire, restore.json conservé, décodage ancien) et 1 test de classification du registre.
- Suite complète : 1 928 tests / 240 suites ; seuls échecs, les tests instables connus (IPC 027, socket 022), réussis seuls.

## Vérification réelle
- Version installée : PID 94362, santé 5/5, signature roadied-cert.
- Mission Control ouvert 1,5 s : aucune des sept fenêtres mesurées n’a changé de taille ni de position.
- Journal : `layout_paused_mission_control` puis `layout_resumed_mission_control` (1 700 ms).

## Limites
- Les fenêtres déjà rétrécies gardent leur taille tant que leur stage reste masquée ; elles reprennent leur
  taille à l’affichage de la stage. restore.json retient encore leurs anciennes frames visibles jusque-là.
- Incident pendant la vérification : trois changements de stage lancés sans préciser l’écran ont agi sur le
  bureau 1 du LG (Firefox masqué puis réaffiché) ; l’utilisateur a réaffiché la stage depuis le rail.
- Preuves visuelles : correction sans interface propre ; mesures CGWindowList et journal à la place.
