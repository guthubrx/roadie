# Correction153 — Aperçu réel et transparence du glisser

Statut : Completed. Priorité P1. Le3novembre2026.

## Demande et cadrage
L'utilisateur observe le retour des aplats verts lors d'un glisser, malgré l'aperçu réel auparavant confirmé. Il demande un contenu de fenêtre légèrement transparent, avec visibilité réglable et choix d'une fenêtre opaque ou d'un aplat. Le paramètre existant fx.drop_preview vaut toujours real et les permissions sont présentes ; ne pas prétendre qu'un redémarrage est prouvé comme cause.

Clarification reçue : la fenêtre doit rester représentée sous le pointeur. L’utilisateur choisit explicitement une copie figée et transparente, comme OmniWM. La destination garde son aperçu distinct. Visibilité proposée85%,100% opaque ; taille50% comme OmniWM, réglable jusqu’à100%. La fenêtre sous le pointeur en mode natif non capturé n'est pas modifiée par une opération privilégiée. Aucun changement des protections ou préférences macOS. Le suivi réel des voisines reste indépendant.

## Histoires et critères d'acceptation
- US1 Retrouver le contenu : un glisser natif de fenêtre effectivement reconnu reste admissible même lorsque la vérification AX du titre arrive après le premier mouvement. Un contrôle, un onglet ou un resize ne devient pas un déplacement sans preuve d'un vrai mouvement de cette même fenêtre, CG ID/PID exacts.
- US2 Choisir le rendu : Paramètres > Effets garde le choix contour/réel à destination et ajoute le rendu sous le pointeur (contenu/contour/aucun), une visibilité10–100% et une taille25–100%.85% de visibilité et50% de taille par défaut ;100% de visibilité donne une copie opaque. Valeur invalide rejetée. Lecture des anciennes configurations conservée.
- US3 Garder le bon contenu : la copie sous le pointeur capture la fenêtre avant sa remise en page et reste figée pendant le glisser, comme OmniWM. Mise à l’échelle uniforme, ratio conservé. La vraie fenêtre peut continuer sa remise en page à destination selon le réglage existant. Une capture au plus par geste ; aucune capture par mouvement ni au repos.
- US4 Revenir proprement : relâchement = vraie fenêtre au cadre final, opacité d'origine ; Échap = cadres initiaux. Erreur, fermeture, désactivation, nouvelle génération ou arrêt = aucune image ni fenêtre cachée abandonnée. Une capture tardive ne peut réafficher une cible périmée.
- US5 Persistance : le choix et le niveau survivent au rechargement de configuration et au redémarrage. Aucune nouvelle permission demandée pendant un geste.

## Validation
Tests purs du mouvement confirmé, identités, exclusions, configuration et catalogue FR/EN. Tests d'intégration des captures tardives, du dernier ratio, de la restauration, du dépôt et de la concurrence d'écriture. Essais Mac sur fenêtres fictives, même écran et entre écrans, paramètres puis gestes réels ; preuve HTML légère. Mesurer les captures et la consommation, sans attribuer au GPU une mesure du seul daemon.
