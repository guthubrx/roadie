# Revue indépendante151 — code

Tâche Bridget cc3bf754-e2db-48bc-9477-e31b57fa58b1, source a58f4d509228b4fe03808bd375ee5f0086f6d27e. Lecture seule, sans shell ni essais natifs. Le relecteur ne revendique pas le diff complet ni la lecture de tous les artefacts. Verdict initial : corrections demandées.

- R1 : prochain geste pendant drainage. Corrigé : le contrôleur attend la fin de la transaction précédente puis acquiert un relevé frais en arrière-plan. Un relâchement arrivé pendant cette attente reste en file. Une nouvelle pression ordinaire ne révoque plus un dépôt en fin. Test avec writer bloqué puis deux gestes successifs.
- R2 : clic quand le cache vient d'être invalidé. Corrigé : relevé asynchrone hors callback avant rejeu. Identité CG/PID et surface devant exigées ; une nouvelle pression invalide la tâche. La recommandation de rejouer vers une cible disparue est refusée : cela cliquerait une autre fenêtre. Le refus pour cible changée est journalisé.
- R3 : géométrie BSP non représentable. Plus aucun repli en écriture libre de la source. Une fin sans géométrie finale valable retourne commit_rejected.
- R4 : configuration uniforme. begin utilise publishedConfig comme la capture et valid.
- Coût : cadres originaux préparés une seule fois dans Session. Pas d'optimisation spéculative du moteur candidat.
- Contexte changé : abandon sans restauration volontaire pour ne pas réappliquer une disposition périmée. Dépôt sans candidat : retilage normal à la fin ; à vérifier nativement.

Observation native supplémentaire : le conteneur Notification Center CG18, PID732, layer21, alpha1, frame1512×982 couvre l'écran interne sans être une fenêtre interactive. La première version refusait donc tous les gestes sur cet écran. Le filtre exclut seulement le conteneur sans sous-rôle et au cadre exact d'un écran. Un panneau plus petit reste bloquant. Test de régression ajouté.

La première activation a santé5/5, mais le premier geste a montré ce défaut. Elle ne constitue pas la validation finale. Recompilation et nouvel essai requis.

## Relecture finale

Tâche ffeba36c-0ea9-45e2-83d1-bfa6eefcd6c7 sur76cc78736c62ba4c1933caebf54fa443317f23b3 : aucun défaut bloquant, corrections R1-R4 confirmées par lecture. Sans shell ni mesures natives.

Réserves traitées par lecture et validation : effectiveConfig dans refresh/init recharge et publie la configuration de façon synchrone sous verrou ; begin/valid/capture lisent ensuite la même valeur publiée. Le rechargement périodique doit continuer pour détecter une édition du fichier, donc ne pas le remplacer par une simple lecture publiée. Un relevé de clic qui échoue reste refusé par prudence ; son absence de journal est une limite mineure conservée. commit_rejected réveille bien scheduler.buttonsReleased via abandon/completed, qui reprend le retilage ; pas de persistance périmée. La « course rare » signalée sans séquence reproductible reste hypothétique ; le test writer bloqué valide la séquence explicitement refusée auparavant. Aucune troisième boucle de revue générale.

Tests parent après corrections :19tests151,2480tests/375suites et28tests de scripts réussis.

## Défaut natif du rejeu découvert après revue

Le test natif Ctrl+clic a montré une boucle de recapture. Un tap de validation indépendant a observé que les événements repostés gardaient le userData151209 de l'émetteur initial, malgré setIntegerValueField sur la copie. Le champ seul ne change pas la source CG ; le système réapplique ses attributs lors du post. Les deux gestes ont été désactivés par leurs réglages et la configuration rechargée pour arrêter la boucle. Aucun arrêt forcé ni droit changé.

Correction : source CG privée possédée par le contrôleur, userData fixé sur cette source, copie des deux événements puis setSource avant post. Les flags d'origine sont conservés. Le test vérifie maintenant aussi CGEventSource(event:).userData et que la source d'origine reste inchangée. La preuve native finale doit confirmer le passage d'une seule paire avec le nouveau marqueur et l'ouverture du menu.

Le pilote de preuve initial lançait sa capture suivante sans attendre la fin effective de l'action BTT asynchrone. Il attend désormais un reçu écrit par le producteur après son up. Le redimensionnement de100points a ensuite donné +100points, voisines -100points, sauvegarde de l'arbre ; Échap a restauré les trois cadres sans modifier l'arbre et Ctrl+glisser a permuté A/C. Ces gestes restent à revérifier sur le dernier binaire du correctif de rejeu.
