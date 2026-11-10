#154 — Fiabilité du glisser entre écrans

Correction autorisée le10 novembre2026. Examiner les anomalies de déplacement sur sept jours, corriger les causes confirmées, installer sur le Mac puis intégrer dans main et nettoyer.

## Exigences
- Un glisser peut quitter un écran, y revenir ou être déposé sur un autre écran, même depuis une fenêtre agrandie par Roadie.
- Ctrl + glisser survit à un changement de focus entre écrans sans changement de géométrie.
- Une annulation restaure les cadres ; une commande concurrente gagne sans dépôt périmé.
- La copie, son opacité et son échelle conservent les réglages utilisateur.
- Le fond transparent de Notification Center ne masque pas les fenêtres pour le titre, les bords ou le focus ; les vrais panneaux restent bloquants.
- Les abandons du suivi direct et les échecs de dépôt ont une raison observable.
- Les preuves brutes et les données utilisateur restent hors Git.

## Limites d’observation
La rotation disponible commence le7 novembre2026 à15:41:47UTC. Les jours précédents ne sont plus présents. Les refus AX et délais de capture sont à qualifier, sans supposer un défaut de Roadie.
