# Diagnostic et réutilisation

Le 18 octobre, le réglage installé resize_handles est vrai, le mode est spatialBsp et l'écart est 10 points. Trois fenêtres iTerm sont présentes sur l'écran interne. Les fenêtres du processus borders dépassent leurs cadres de 12 points sur chaque côté. CoreGraphics les déclare layer 0 et onscreen=true. Le test d'occupation de DividerResizeCoordinator utilise leur rectangle entier ; il couvre donc les interstices pourtant transparents.

Le filtre de tuilage existant exclut déjà les fenêtres inconnues sans titre ni AX, mais ne distingue pas les bordures d'un vrai panneau illisible. Réutiliser ses attributs, avec une exception étroite pour borders au seul point d'occupation. Ne pas élargir cette exception à toutes les fenêtres exclues du tuilage.

La poignée actuelle mesure 2 × 24 points et utilise une couleur secondaire atténuée. Améliorer son contraste et son épaisseur à l'intérieur du même rectangle libre. Le curseur indique déjà le sens du déplacement.
