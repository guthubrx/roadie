# 061 - Vue d’ensemble des bureaux et stages

Statut : In Progress. Date : 2026-10-24. Dépendances : 053, 055, 056, 057, 058, 060.

## Demande initiale et cadrage conservé
L’utilisateur retient Archipel et Baies, avec leur loupe indépendante. Le défaut est Archipel avec loupe. Un balayage trois doigts vers le haut doit ouvrir cette vue via BetterTouchTool. Toutes les entrées passent par la CLI ; un raccourci interne reste facultatif. Complément : la loupe suit la souris et son grossissement, donc la réduction des autres zones, est paramétrable.

Résultat : une carte globale des contextes Roadie, avec une hiérarchie écran > bureau > stage > fenêtre. Consulter ne change pas le travail en cours. Une activation explicite rejoint la fenêtre dans son contexte d’origine. Les maquettes /tmp/roadie-archipel-baies-loupe.html servent de référence visuelle, pas de preuve native.

## US1 - Voir et rejoindre les contextes (P1)
La vue montre les écrans présents, leurs bureaux occupés, nommés ou actifs, leurs stages occupées ou nommées et leurs fenêtres. Les identités comprennent écran/bureau/stage, sans fusion des homonymes. Une fenêtre réduite ou masquée reste accessible si son identité est confirmée. Un clic sur une fenêtre ou Entrée rejoint son contexte ; Échap annule. Les flèches et Tab déplacent la sélection. L’état actif et la sélection sont distincts. La fenêtre sélectionnée reste repérable.

## US2 - Choisir la disposition et consulter avec la loupe (P1)
Archipel répartit les écrans en colonnes séparées par une diagonale, les bureaux en îlots. Baies utilise des bandes par écran, avec les bureaux dans chaque bande. Les deux gardent l’ordre des contextes. Le choix et l’interrupteur de loupe sont disponibles dans la vue et dans Réglages Roadie > Vue d’ensemble. Le survol d’un bureau déplace la loupe après une courte stabilisation. Un changement de géométrie sans mouvement réel ne déplace pas à lui seul la loupe. Le grossissement demandé, de 100 à 250 %, vaut 150 % par défaut et règle la taille de l’aperçu de fenêtre. Le grossissement effectif est limité pour garder les autres contextes accessibles. Aucun survol n’active ni ne réaffecte une fenêtre. Les miniatures gardent leurs proportions et leur contenu entier.

## US3 - Déclencher et régler (P1)
`roadie overview show|toggle|hide|status` fonctionne sans raccourci interne. Les réglages persistants sont activé, disposition, loupe, grossissement et raccourci facultatif capturé au clavier. Un raccourci vide ne réserve aucune touche. Le balayage BTT trois doigts vers le haut appelle la CLI, sans modifier Cmd+Tab ni le plein écran Roadie. Les gestes remplacés sont sauvegardés et relus par l’API officielle.

## Exigences et critères de réussite
- FR01 : inventaire commun au sélecteur, navigation sans réaffectation.
- FR02 : deux dispositions et quatre combinaisons disposition/loupe fonctionnelles.
- FR03 : survol stable, sans lecture AX, disque ni capture déclenchée par mouvement.
- FR04 : grossissement borné ; autres bureaux restent dans le document consultable, sans chevauchement des zones.
- FR05 : inventaire acquis hors fil principal selon le chemin existant, tâches annulables ; pas de minuterie de capture après fermeture.
- FR06 : CLI stricte, erreurs explicites si aucun récepteur ; accès indépendant de target-mode.
- FR07 : configuration ancienne inchangée hors clés ajoutées ; défauts sûrs et aller-retour des réglages.
- FR08 : activation, Échap, flèches, clic, survol et changement de disposition vérifiés en tests et parcours natif dans la mesure des accès disponibles.
- SC01 : 11, 32 et 64 fenêtres, plusieurs écrans, bureaux homonymes et stages vides testés sans fenêtre perdue ni double identité.
- SC02 : les quatre combinaisons et les limites 100/150/250 % ont des rectangles positifs, bornés et disjoints. En forte densité, le défilement conserve des cibles utilisables ; aucune promesse de lisibilité infinie sur une page.
- SC03 : docs FR/EN, preuve visuelle et limites, tests, installation, intégration et push vérifiés.

## Hors périmètre
Remplacer les Spaces natifs, déplacer les fenêtres par glisser, inventer des fenêtres absentes, nouvelle dépendance, mesure comparative sur une machine chargée. Aucun changement des raccourcis existants du sélecteur.

## Retour utilisateur après installation
Le geste physique ouvre bien Roadie, confirmé par l’utilisateur. La carte doit supprimer les colonnes démesurément hautes et étroites. Les stages reçoivent une place proportionnée à leur contenu et leurs cartes utilisent les deux dimensions. Les îlots restent compacts. La loupe agrandit aussi la fenêtre survolée, dans les deux dispositions, en conservant son image entière. Le pourcentage règle la taille de cet aperçu. Le geste Mission Control concurrent est désactivé après sauvegarde, sans supprimer les autres raccourcis.

## Référence graphique imposée après comparaison
Le rendu installé a été refusé : grands cadres de bureaux, cartes et barre d’outils éloignées de la maquette. La référence utilisateur est /tmp/roadie-archipel-cinq-propositions.html, avec la capture à 32 fenêtres et les contrôles de /tmp/roadie-archipel-baies-loupe.html. Le port doit reprendre la composition, les proportions, les titres, les séparations obliques et les légendes. Aucun cadre massif autour des bureaux. La loupe de fenêtre agit dans la composition, sans carte flottante superposée. Les images fictives de la maquette servent uniquement au test comparatif natif ; l’application continue d’utiliser les captures réelles du cache partagé.

## Épuration et mode d’affichage
À la demande finale : pas de ligne d’état, de logo ni de nom Roadie/Vue d’ensemble dans l’en-tête, pas de compteurs globaux. Conserver les commandes de disposition/loupe et les repères de contexte. L’utilisateur précise qu’il vise l’équivalent de Mission Control ; le plein écran natif macOS n’est pas requis. Choix : panneau sans bord couvrant tout l’écran, au-dessus du bureau/Dock, sans créer de Space. Échap retire immédiatement cette vue. L’écoute clavier temporaire est supprimée à la fermeture.
