# Revue indépendante152

Source relue :e3392f570b49c66396bb331f9574589f0377c57a. Tâchef57e6cdc-3126-4b5c-bc24-c0052c057867. Lecture seule, pas de shell ni tests relancés par le relecteur. Résultat complet conservé hors Git.

Verdict : pas de défaut prouvé dans le calcul du sens. Un risque de dépendance à un cache vide et des validations complémentaires demandés. Le relecteur confirme l'ordre du rail, la convention de déplacement des fenêtres, la protection de génération et l'absence de nouveau minuteur/dépendance. Potentiel de simplification identifié :0ligne à comportement constant.

## Traitement des constats

1. Écrans provenant seulement du cache de geste : le pipeline de placement transmet désormais observed.displays jusqu'au runtime. Pour un appel sans relevé explicite, SnapshotService prend le cache puis provider.displays(), lecture AppKit sans AX. Un test vide le cache et vérifie encore l'entrée depuis le parking.
2. Retarget rapide avec sens opposés : test ajouté, la seconde génération gagne et la première cible finale n'est jamais réappliquée après le changement.
3. Bouclage via la vraie commande : test paramétré next et prev ajouté sur six stages. Il vérifie le déplacement après la commande, en plus de la fonction pure.
4. Départ réécrit pendant un effet existant : risque non reproduit. EffectAnimator reprend les états en cours lorsque l'identifiant est repris ; les nouvelles valeurs from ne remplacent pas les états existants. Test du changement rapide ajouté au constat2.
5. Convention de coordonnées et repli : commentaire ajouté. Dans le repère AX, y croît vers le bas. Hors navigation, le déplacement historique vers la gauche reste conservé.

La limite native du bord supérieur reste ouverte. La revue ne remplace pas le choix utilisateur sur un rendu temporaire par capture. Aucune capture animée n'est ajoutée par ces corrections. Les15tests ciblés /4suites passent après les changements. Suite complète après corrections :2487tests /377suites verts en80,105s. Les compléments de revue ne sont pas encore chargés sur le Mac ; le binaire actif reste celui de la validation native décrite dans validation.md.

## Revue des captures, commit73a5f6a
Tâche141d79bd-296e-41f2-a7ba-2e4925f03361, reçue et garde fermée. Aucun défaut bloquant prouvé par lecture, sans exécution des tests par le relecteur. Métadonnées rafraîchies au démarrage du rail et sur changement d’écran ; origine CGDisplayBounds courante. Capture injectable dans le runtime, tests du placement unique et du retarget de scène. Masque extrait et testé avec trous qui se chevauchent. Raisons de refus capture distinguées (permission/métadonnées/occupé) et durées source/cible journalisées même si retour trop tardif. immediateWindowIDs conservé dans la branche scène ; lecteur d’écran évité quand le runtime est arrêté. Les fenêtres non gérées absentes du relevé peuvent encore apparaître dans la scène : elles restent figées pour cette courte transition, limite connue.

Mesure SDK native8captures :55–131ms. Le seuil40ms ne permettait pas le rendu ; seuil120ms et animation lancée dès la source, en parallèle du placement/capture cible. Focus entrant différé après la fin de l’animation pour ne bloquer ni la source ni le rendu. Annulation avant départ de tâche : aucune capture obsolète lancée. Ces compléments sont vérifiés par le responsable ; pas de second verdict indépendant inventé.
