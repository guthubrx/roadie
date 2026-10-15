# ADR 012 — Distinguer la présence et la visibilité des fenêtres

Date : 2026-10-15. Statut : accepté dans la correction 036.

Le relevé de placement utilise les fenêtres du bureau visible. Un plein écran natif rend certaines fenêtres toujours ouvertes absentes de ce relevé. Une expiration seule ne prouve pas une fermeture.

Décision : un inventaire CoreGraphics en lecture seule confirme les couples identifiant/PID des membres déjà persistés. Cette preuve conserve leurs groupes et leur représentation dans le rail. Elle ne crée aucune fenêtre dans le relevé de placement. Un signal de fermeture confirmé et les observations courantes restent prioritaires.

Conséquences : les fenêtres d’un Space inactif ne sont plus confondues avec des fenêtres fermées. Aucun changement de format persistant ni d’IPC. Un inventaire indisponible conserve le repli antérieur. Coût : une lecture CG supplémentaire, linéaire, sans appels AX par fenêtre.
