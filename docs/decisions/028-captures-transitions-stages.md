# 028 — Captures courtes pour les transitions de stages

Statut : accepté par l'utilisateur le 3 novembre 2026, validé en fonctionnement.

Les écritures AX ne peuvent pas déplacer certaines fenêtres tuilées au-dessus du bord supérieur. La correction du sens et du départ depuis le parking ne suffit donc pas pour montrer une arrivée depuis le haut.

La commande fournit la zone du scope depuis son relevé. Le rail fournit ses métadonnées ScreenCaptureKit déjà chaudes. Deux captures réduites à deux millions de pixels chacune servent à l'animation : source avant placement et cible après le placement final. Le filtre exclut l'application Roadie. Un panneau sans focus ni capture de clic affiche des couches Core Animation. Les fenêtres stationnaires sont retirées du masque par soustractions géométriques, même lorsqu'elles se chevauchent.

Le dispatcher interactif existant applique une seule fois les cadres finaux. Le permis de génération couvre aussi les retours de capture et l'animation. Le minuteur existant contrôle les échéances : 120 ms pour la source puis 200 ms pour le placement et la cible, avec au plus un tick de 33 ms avant révélation directe. Une capture tardive ne réaffiche jamais le panneau. Un seul appel de capture de scène peut rester en vol. Il n'y a ni capture par image, ni image persistée sur disque, ni réglage macOS modifié.

Les durées, courbes et intensités Roadie restent utilisées. Le contenu est figé pendant la courte transition. Sans permission, à froid ou sous charge, le placement reste direct. Le plafond représente environ 16 Mo pour les deux images RGBA, hors surfaces de rendu et allocations du système. La consommation CPU/GPU réelle doit être mesurée et ne peut pas être déduite de ce plafond.

Référence API : https://developer.apple.com/documentation/screencapturekit/sccontentfilter et SCScreenshotManager du SDK macOS installé. Aucun framework tiers ajouté.

Mesures initiales du SDK : huit captures de55 à131ms (dont un premier appel froid). Le mouvement commence dès la capture source acceptée, pendant le placement et la capture cible. La durée de l’animation ne s’ajoute donc plus aux deux préparations complètes. Le focus de la fenêtre entrante attend le placement final ; il ne bloque plus le lancement de la capture source. La source lente passe en direct au-delà de120ms.

Le focus AX est finalement déclenché après le retrait des images. Les mesures intégrées montraient qu’un focus pendant le mouvement consommait le budget cible et bloquait le fil de rendu. Sur dix bascules finales : neuf animations complètes de294 à356ms, une bascule directe sous dépassement. Mesure détaillée dans la validation152.
