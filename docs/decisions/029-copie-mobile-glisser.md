# ADR029 — Copie mobile pendant le glisser

Statut : accepté, le 3 novembre 2026. Session153.

## Contexte
La vraie fenêtre est déjà déplacée et remise en page à destination en mode réel. Elle ne suit donc plus le pointeur. Une vérification tardive de la barre de titre pouvait empêcher ce mode pour tout le geste. L’utilisateur choisit une copie transparente et figée sous le pointeur, comme OmniWM.

## Décision
Une capture ScreenCaptureKit initiale, limitée à deux millions de pixels, alimente un panneau non activant. Le panneau garde le ratio de départ et le point saisi à l’échelle choisie. Seule sa position change pendant le glisser. Le contenu est figé. Les réglages sont indépendants : contenu/contour/aucun sous le pointeur, visibilité10–100%, taille25–100%, contour/réel à destination. Défauts : contenu,85%,50%.

Les déplacements natifs restent visibles pendant la préparation. La prise en charge nécessite une image prête et une preuve : barre de titre admise sans déplacement, ou mouvement de la même fenêtre suivant le pointeur sans changement de taille. L’identité CG/PID est stricte. La fin synthétique du glisser natif utilise le point courant. Ctrl+glisser réutilise le même rendu et son écrivain existant. Le redimensionnement reste inchangé.

## Conséquences
Aucune capture à chaque mouvement, aucun nouveau service, aucune modification des protections macOS. Une capture absente garde le déplacement natif visible. L’annulation et le relâchement retirent le panneau et libèrent l’image. Une capture tardive ne peut réactiver un ancien geste. Le délai de préparation et la consommation réels restent à mesurer sur le Mac, sans garantie de fréquence ni de coût GPU.

L’opacité des fenêtres d’autres applications n’est pas modifiée. Une sonde sur une fenêtre fictive a montré qu’un retour0 de SLSSetWindowAlpha ne changeait pas l’alpha lu. Le parcours privilégié de Yabai requiert une extension injectée et des protections réduites ; il est exclu. La copie figée a été explicitement acceptée par l’utilisateur.

## Sources
- OmniWM : https://github.com/OmniNull/OmniWM/blob/077edbc98347a825ccba87a20fa7fa22b26c61fb/Sources/OmniWM/Core/Layout/Niri/DragGhostController.swift
- Yabai : https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/osax/payload.m
