# Spécification 062 - Fenêtres rétrécies par Mission Control

Statut : correction, validée d’office (défaut signalé le 24 octobre 2026).

## Problème
Des fenêtres seules sur leur stage (Thunderbird, iTerm2, X, KeePassXC) deviennent très
petites (203×116, 276×158, 449×257, 715×411…). Leurs aperçus dans la vue d’ensemble et le
rail paraissent zoomés. iTerm2 reste petit même après l’affichage de sa stage.

## Cause mesurée
- Les petites tailles sont les tailles normales multipliées par un même facteur
  (1837×2114 × 0,244 = 449×516 ; 1837×1052 × 0,244 = 449×257).
- Pendant Mission Control, CGWindowList rapporte des cadres réduits et déplacés
  (T3 Code 1837×2114 → 575×662). Après fermeture, les fenêtres des stages masquées
  restaient réellement réduites (Thunderbird et iTerm2 1155×664), les visibles non.
- Le masquage réécrit la taille observée ; le relevé enregistre ces cadres dans
  stages.json ; restore.json les retient comme dernière frame visible ; l’arrêt de
  Roadie les réapplique.
- Une écriture d’iTerm2 en échec (−25204, sans relecture) était acceptée comme réponse.

## Exigences
- FR-001 : aucune écriture ni mémorisation de cadre pendant Mission Control.
- FR-002 : garer une fenêtre ne change jamais sa taille.
- FR-003 : une écriture sans réponse de l’application est reprise, pas acceptée.
- FR-004 : pause et reprise journalisées (`layout_paused_mission_control`, `layout_resumed_mission_control`).

## Hors périmètre
Nettoyage actif des cadres déjà pollués : ils guérissent quand la stage est affichée.
