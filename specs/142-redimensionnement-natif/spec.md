# Spécification : redimensionnement natif fluide

**Branche** : `session-142-redimensionnement-natif`
**Créée** : 2026-10-31
**Statut** : In Progress
**Demande** : « plus fluide même sans poignées », proposition détaillée puis « go ».

## Scénarios utilisateur et tests

### US1 — Les voisines suivent le bord natif (P1)
L’utilisateur redimensionne une fenêtre tuilée par son bord ou son coin habituel. Les voisines suivent avant qu’il relâche. Aucun nouveau raccourci ni poignée n’est nécessaire.
- Dans une stage à arbre BSP, agrandir/réduire par chacun des bords internes fait évoluer les fenêtres concernées pendant le geste.
- Le déplacement d’un coin peut déplacer deux séparations.
- La fenêtre saisie conserve sa taille native pendant le geste : Roadie ne lui écrit pas de cadre.
- Un clic de contenu, un déplacement de titre et les fenêtres flottantes ne déclenchent aucun suivi de taille.

### US2 — Un geste reste réactif sous charge (P1)
Une voisine lente ne bloque pas le traitement du geste ni les autres applications.
- Une seule cible attend par fenêtre ; la plus récente remplace la précédente.
- Aucun rattrapage en cascade des anciennes tailles après relâchement.
- Une fin de geste ou une commande nouvelle invalide les demandes anciennes.

### US3 — Les proportions finales restent stables (P1)
Au relâchement, les proportions obtenues sont conservées et retrouvées après reprise de la disposition.
- Le cadre final est relu même si sa notification arrive après le bouton relâché.
- Une fermeture, un changement de bureau/stage/écran ou de configuration arrête proprement le suivi.
- Les minima connus et les refus des applications restent protégés ; aucune oscillation.

## Exigences
- **FR-001** : suivre en direct les bords/coins natifs des fenêtres d’une stage active à arbre BSP ; aucun changement des autres modes dans cette session.
- **FR-002** : confirmer une variation de taille réelle avant d’adapter les voisines ; ne jamais écrire la fenêtre saisie pendant son geste natif.
- **FR-003** : ne bloquer ni le traitement des entrées ni les autres applications sur les réponses d’une voisine lente.
- **FR-004** : conserver uniquement la dernière cible en attente de chaque fenêtre et rejeter les travaux obsolètes.
- **FR-005** : conserver les proportions finales dans une transaction ; un état concurrent ne doit jamais être écrasé.
- **FR-006** : respecter les tailles minimales, les feuilles absentes et les refus ; arrêter sur changement de contexte.
- **FR-007** : garder les protections des clics/glissers ordinaires, du plein écran et des poignées existantes.
- **FR-008** : produire une comparaison avant/après avec le même geste et distinguer mesures logicielles, mesures natives et limites.

## Critères de réussite
- **SC-001** : au moins une voisine change effectivement de cadre avant le relâchement dans le parcours natif contrôlé.
- **SC-002** : aucune écriture Roadie sur la fenêtre saisie pendant le geste ; aucun ancien résultat appliqué après invalidation dans les tests de concurrence.
- **SC-003** : au plus une mise à jour en attente par fenêtre, indépendamment du nombre de mouvements.
- **SC-004** : les proportions finales restent identiques après une nouvelle passe et une relecture de l’état.
- **SC-005** : objectif expérimental p95 du délai cadre observé → voisines visibles inférieur à deux rafraîchissements sur applications réactives ; indiquer explicitement tout dépassement ou impossibilité de mesure. Ce chiffre n’est pas une promesse sur les applications lentes.

## Hypothèses, dépendances et limites
Périmètre initial validé : moteurs `usesTreeEngine`, sans nouveau mode de disposition. Les commandes, projets, écrans, rail et choix utilisateur restent conservés. Réutiliser les sessions 017, 043, 062, 068, 083 et 086. Le code d’OmniWM fournit une référence de comportement ; aucun code GPL n’est copié. L’application contrôle son rendu natif et peut refuser une taille. L’essai réel doit utiliser des fenêtres dédiées sans contenu privé.
