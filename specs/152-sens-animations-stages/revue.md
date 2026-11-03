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
