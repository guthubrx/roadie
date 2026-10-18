# 050 - Double-clic sur la barre de titre

Demande validée le 18 octobre 2026 (`/my.specify-all 1 a 4`, point 3), issue de la
comparaison avec TrellisWM (« Double-click frames the window on its own »).

## Besoin

Un double-clic sur la barre de titre d'une fenêtre gérée doit l'afficher seule, avec la
maximisation Roadie qui garde le rail libre. Un second double-clic rend la disposition.

## Contrainte

macOS agit déjà sur ce double-clic (agrandir ou réduire, réglage « Double-cliquer sur la
barre de titre d'une fenêtre pour… »). Roadie ne peut pas consommer le clic sans
intercepter tous les clics en permanence. Roadie n'agit donc que si ce réglage vaut
« Ne rien faire ». Sinon, il ne fait rien et la santé le signale (session 049).

## Exigences

- R1 Double-clic dans la bande de titre d'une fenêtre gérée et tuilée, hors marges des
  boutons : `toggle maximize` sur cette fenêtre.
- R2 Réglage `[experimental.titlebar_context_menu] double_click_maximize`, booléen, défaut
  `false`, lu à chaud, indépendant du menu par clic droit ; réutilise la hauteur et les
  marges de la barre de titre.
- R3 Aucune action si l'action macOS du double-clic n'est pas « Ne rien faire ».
- R4 Coût : aucun relevé pour un clic simple ; relevé seulement sur un double-clic.
- R5 La santé (contrôle `macos-window-settings`, session 049) signale le conflit quand le
  double-clic Roadie est activé et que l'action macOS n'est pas « Ne rien faire ».
- R6 Docs FR/EN et fenêtre des réglages alignés (l'exemple de configuration ne documente pas cette section).
