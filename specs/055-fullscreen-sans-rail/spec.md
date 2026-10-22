# Session 055 - Plein écran Roadie sans rail

Demande utilisateur : Ctrl gauche + Alt gauche + F agrandit la fenêtre sans
plein écran natif macOS et cache le rail, y compris au survol. Répéter restaure
la disposition. La maximisation avec rail reste distincte.

Réutiliser toggle fullscreen : son intent explicite sans réserve du rail fait
foi, même avec une seule fenêtre et sans hide_on_maximized. Seul l'écran de
la stage active concernée est masqué ; une simple grande fenêtre ne suffit pas.
À la sortie ou au changement de stage, le rail retrouve son état/pin/auto-hide.
Le mode Dock existant reste inchangé hors de ce plein écran.
Créer le raccourci via API BetterTouchTool, sans conflit ni changement Karabiner.
Conserver les raccourcis Option+F maximize et Option+Maj+F natif.
