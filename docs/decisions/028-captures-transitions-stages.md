# 028 — Captures courtes pour les transitions de stages

Statut : accepté par l'utilisateur le 3 novembre 2026, validation en cours.

Les écritures AX ne peuvent pas déplacer certaines fenêtres tuilées au-dessus du bord supérieur. La correction du sens et du départ depuis le parking ne suffit donc pas pour montrer une arrivée depuis le haut.

La commande fournit la zone du scope depuis son relevé. Le rail fournit ses métadonnées ScreenCaptureKit déjà chaudes. Deux captures réduites à deux millions de pixels chacune servent à l'animation : source avant placement et cible après le placement final. Le filtre exclut l'application Roadie. Un panneau sans focus ni capture de clic affiche des couches Core Animation. Les fenêtres stationnaires sont retirées du masque par soustractions géométriques, même lorsqu'elles se chevauchent.

Le dispatcher interactif existant applique une seule fois les cadres finaux. Le permis de génération couvre aussi les retours de capture et l'animation. Le minuteur existant contrôle les échéances : 40 ms pour la source puis 200 ms pour le placement et la cible, avec au plus un tick de 33 ms avant révélation directe. Une capture tardive ne réaffiche jamais le panneau. Un seul appel de capture de scène peut rester en vol. Il n'y a ni capture par image, ni image persistée sur disque, ni réglage macOS modifié.

Les durées, courbes et intensités Roadie restent utilisées. Le contenu est figé pendant la courte transition. Sans permission, à froid ou sous charge, le placement reste direct. Le plafond représente environ 16 Mo pour les deux images RGBA, hors surfaces de rendu et allocations du système. La consommation CPU/GPU réelle doit être mesurée et ne peut pas être déduite de ce plafond.

Référence API : https://developer.apple.com/documentation/screencapturekit/sccontentfilter et SCScreenshotManager du SDK macOS installé. Aucun framework tiers ajouté.
