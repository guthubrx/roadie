# Session 144 — Effets réglables et aperçu réel de destination

Date : 2026-10-31. Statut : Implemented — livré le 2026-10-31. Branche : session-144-effets-reglables.
Dépendances : 142 (writer interactif), 143 (voisines pendant le glisser), 061/071 (vue d’ensemble), 078 (aperçu réversible), 023/057 (paramètres).

## Demande initiale et cadrage conservé
L’utilisateur demande des effets comme ceux des compositeurs Wayland, réglables et désactivables. Il précise : « la zone dans laquelle je la relâche […] un rectangle vert […] plutôt que […] le ghost vert […] la fenêtre ». Un changement 16:9 vers 9:16 doit montrer la vraie remise en page du contenu.

Demande reformulée : ajouter des effets réglables à Roadie et un mode qui place temporairement la vraie fenêtre dans sa destination, avec la bonne mise en page, puis confirme ou restaure le placement. Préserver le focus, les affectations et la réactivité. Mesurer le coût réel, y compris dans l’application qui refait sa mise en page et dans WindowServer.

Apport du cadrage : distinguer une animation visuelle et un placement réel. Une image étirée ne constitue pas l’aperçu réel demandé. Dans ce mode, la source peut quitter le pointeur ; le pointeur choisit toujours la destination. Les effets ne changent pas la disposition choisie.

## Scénarios et acceptation
### US1 — Régler les effets (P1)
Dans Paramètres > Effets, activer ou désactiver les animations. Choisir Aucun, Sobre, Souple ou Expressif. Régler chaque action : déplacement/réorganisation, changement de stage, apparition/disparition des interfaces, rail, lanceur, sélecteur, vue d’ensemble. Choisir la courbe, la durée et l’intensité. Pour un ressort, régler sa raideur et son amortissement ; la durée reste réservée aux courbes temporelles.
Acceptation : les valeurs restent après réouverture ; une modification s’applique sans relance ; désactiver supprime les transitions et conserve les mêmes cadres finaux. Les réglages et aides existent en français et en anglais. La page fournit un aperçu sans déplacer les applications.

### US2 — Voir la vraie destination (P1)
Choisir Contour ou Aperçu réel, indépendamment du suivi des voisines de la session 143. Pendant un dépôt sur le bureau depuis un titre ou le rail, la vraie source prend la taille du candidat. Le texte se réorganise réellement. Le pointeur continue de choisir les cibles sur la disposition de départ.
Acceptation : un glisser paysage vers portrait montre de nouvelles lignes de texte, sans capture étirée ; des mouvements supplémentaires du pointeur ne déplacent pas la source hors de la destination. Le relâchement conserve la destination. Échap restaure les cadres initiaux, sans changement d’affectation.

### US3 — Interrompre sans perte d’état (P1)
Changer de cible, annuler, ouvrir une autre stage, commencer un nouveau geste ou fermer l’application.
Acceptation : une cible ancienne ne revient pas ; aucune écriture de l’arbre pendant l’aperçu ; un seul dépôt persistant ; aucun focus pris par un panneau décoratif. Une fenêtre épinglée, modale, native plein écran ou non admissible reste exclue. Une application qui refuse une taille conserve ses limites.

### US4 — Connaître et maîtriser le coût (P1)
Seuls les réglages de Roadie décident des animations, indépendamment de macOS. Les mouvements pilotés directement restent immédiats par défaut. L’aperçu réel n’envoie une taille que lorsque sa cible change.
Acceptation : aucun minuteur d’animation ni flux de capture supplémentaire au repos ; coût O(k) par image pour k éléments animés ; nombre de lots en attente borné par application ; absence d’AX et de lecture disque dans le callback de capture souris. Comparaison activé/désactivé sur Roadie, WindowServer et application cible, avec mémoire, CPU et latence. La mesure GPU doit préciser son outil ou son indisponibilité, sans chiffre inventé.

## Exigences fonctionnelles
- FR-001 : politique et calcul de mouvement communs aux fenêtres et interfaces ; reprendre depuis la position courante lors d’un changement de cible. Le ressort conserve sa vitesse.
- FR-002 : réglages persistants, validés, FR/EN, immédiats ; anciens fichiers et réglage du rail compatibles.
- FR-003 : propriétaire unique du glisser ; clic simple, double clic, contrôles de fenêtre et glissers de contenu préservés. Ne déplacer la source que lorsque Roadie possède le geste. L’échec de capture garde le contour et produit un diagnostic explicite.
- FR-004 : Contour/Aperçu réel indépendant de live_drag_preview ; visée figée, source réelle redimensionnée seulement aux changements de candidat. Dépôts internes aux miniatures du rail et de l’overview inchangés.
- FR-005 : annulation/restauration et invalidation par génération ; modèle non persisté pendant l’aperçu ; résultat différé distinct d’une écriture réellement achevée.
- FR-006 : activation/désactivation indépendante de macOS ; ressources d’animation arrêtées à la fin, à l’annulation et à l’arrêt du daemon ; durée de maintien bornée.
- FR-007 : mesures on/off reproductibles, vérification native et preuves visuelles sans document personnel.
- FR-008 : aucun changement de protection système, permission, compte, ni shader arbitraire ; aucune promesse de flou/déformation de fenêtres tierces comme un compositeur. Apparition/disparition en fondu pour les panneaux Roadie ; déplacement réel pour les fenêtres tierces. Un contenu fermé ou protégé n’est pas recréé artificiellement.

## Critères de réussite
- SC-001 : tests de configuration, courbes et reprise ; désactivation dans Roadie donne exactement la cible.
- SC-002 : source réelle et voisines indépendantes (quatre combinaisons), retour à l’origine, dernière cible, annulation et changement de contexte couverts par tests.
- SC-003 : vérifier Finder, navigateur, éditeur et fenêtre à taille imposée ; portrait/paysage, écran interne/externe ; un essai indisponible reste une limite explicite de livraison.
- SC-004 : vérifier qu’une animation terminée ne garde aucun timer actif ; 30 s au repos on/off ; latences p50/p95, RSS et CPU des trois processus. Mesures natives conservées, limites nommées.
- SC-005 : mêmes affectations, configuration hors nouveaux réglages et certificat après installation ; processus chargé et cinq contrôles santé vérifiés.

## Hors périmètre
Pas de nouvelle release implicite. Pas d’API privée nécessitant une injection dans Dock. Pas de remplacement d’un contenu réel par une photo déformée. Les animations de fermeture des applications tierces ne sont pas promises : Roadie ne possède pas leur surface après fermeture. Les effets de disparition configurables concernent ses propres panneaux.

Clarification utilisateur du 31 octobre, pendant implémentation : Roadie doit être indépendant du réglage « Réduire les animations » de macOS. Activer/désactiver dans Roadie fait seul autorité. Le réglage système est conservé, mais ne filtre plus les effets Roadie.

Qualification native du 31 octobre : pendant un glisser possédé entre écrans à Spaces séparés, le cadre AX rejoint la cible, mais WindowServer masque le contenu jusqu’au relâchement. La vraie source reste donc sur son écran initial lorsque le pointeur vise un autre écran ; le contour de destination est affiché et le dépôt reste fonctionnel. Aucun transfert de Space non réversible ni injection n’est ajouté. Limite explicite de l’aperçu réel : même écran.
