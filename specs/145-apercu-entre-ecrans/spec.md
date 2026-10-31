# Session145 — Vraie destination entre écrans

Statut : In Progress. Correction autorisée par le refus explicite du repli entre écrans. Base90703f0962c66952d4beaee04bf7b0ed0be72f41 ; dépendance144.

L’utilisateur veut la vraie fenêtre, avec son contenu remis en page, également lorsqu’il glisse d’un écran à l’autre. Le contour inter-écrans livré en144 ne répond pas à cette demande. Conserver le même geste et les réglages actuels.

FR1 : source réelle visible dans le cadre de destination sur chacun des deux écrans pendant l’appui ; aucune capture étirée ni rectangle de remplacement pour une cible admissible.
FR2 : Échap restaure cadres et appartenance ; aucun changement de stage/arbre avant dépôt. Dépôt conserve la destination sans saut final.
FR3 : préserver clic, double clic, boutons/onglets, focus, glissers rapides et stabilité sur un même écran. Ne pas confondre bouton physique et événement synthétique éventuel.
FR4 : aucune modification de protection macOS, compte ou réglage global des écrans ; pas d’injection Dock. Dépendances, coalescence, budget et refus existants conservés.

Réussite : captures réelles et observations CG/AX montrent le contenu au bon endroit pendant l’appui dans les deux sens, puis une annulation intégrale et un dépôt correct sur AppKit et navigateur. Une frame correcte sans contenu visible n’est pas une réussite. Si aucun mécanisme sûr n’est vérifié, nommer le blocage et ne pas présenter le contour comme solution acceptée.
