# Spécification 067 - Déplacer stages et fenêtres, noms de stage uniques

Demande du 25 octobre 2026. Choix validés : prise par la puce de stage, réordonnancement
aussi dans un même bureau, le bureau affiché reste en place ; une carte glissée sur une
autre stage y envoie sa fenêtre. Ajout pendant la session : une stage nommée est unique
dans tout Roadie (tous écrans et bureaux), doublons existants nettoyés en gardant la copie
occupée, renommage vers un nom pris refusé.

## Comportement
- Puce de stage glissée entre deux groupes de cartes, dans son bureau ou un autre bureau
  du même écran ; bureau sans carte : trait sous sa puce.
- Stage affichée qui part : bascule préalable sur une autre stage de son bureau.
- Carte glissée sur une carte d'une autre stage du même écran : la fenêtre rejoint cette
  stage. Clic simple : ouverture au relâchement. Fenêtre hors relevé : pas de glisser.
- Doublons : écran branché d'abord, puis le plus de fenêtres ; autres copies occupées
  « Nom 2 », copies vides anonymes. Workspace configuré : une seule stage nommée.
