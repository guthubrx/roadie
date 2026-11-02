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
