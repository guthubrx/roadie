# ADR 024 — Effets et propriété du glisser

Date : 2026-10-31. Statut : accepté, vérification native finale en cours.

## Contexte
Le contenu d’une fenêtre ne peut pas se réorganiser à une autre largeur en étirant sa capture. Il faut redimensionner la vraie fenêtre. AppKit conserve la direction d’un glisser natif et peut défaire sa position, y compris sur mouseUp. Le prototype de la session 144 a observé les deux comportements.

## Décision
Réutiliser la session réversible des voisines (ADR 023). Ajouter la source seulement si Roadie possède son geste. Pour le titre, laisser passer le clic, qualifier hors callback puis capter les mouvements avant transmission. Un titre non qualifié conserve son geste natif et le contour. Au relâchement, conserver le point physique pour le dépôt et neutraliser le delta transmis à AppKit. Les contrôles, tabs et contenus ne sont pas des titres admissibles. Depuis le rail, le geste appartient déjà à Roadie.

Réutiliser le dispatcher et les permis de la session 142 pour les animations de cadres. Ajouter un état différé explicite aux résultats de plans animés. Ne jamais annoncer une écriture finale réussie sur la seule planification. Les refus et budgets finaux restent dans le writer commun. Annuler au changement de génération ; maintenir le tick au plus pendant la durée bornée de l’animation. Un mouvement purement visuel ne sauvegarde ni arbre ni affectation.

Partager calcul et horloge entre cadres AX, rail, overview et panneaux. Pas de capture supplémentaire ni d’injection Dock/SIP. Les panneaux Roadie peuvent apparaître/disparaître en fondu. Les fenêtres tierces conservent leur vraie surface et suivent des cadres AX ; leur fermeture ne permet pas de garder artificiellement une surface vivante. Le réglage d’aperçu réel reste indépendant des effets et des voisines.

## Conséquences
Moins de copies d’images et un seul writer. Une application lente peut retarder sa propre remise en page ; les autres PID continuent. Les callbacks de souris ne font ni AX ni disque. La qualification doit être prête avant la capture ; sinon repli sûr sur le contour, avec limite explicite. Une écriture AX déjà engagée reste non annulable entre deux attributs.

Les animations globales sont désactivées par défaut ; activer permet les profils et surcharges. Cela peut rendre immédiates les anciennes transitions de panneaux, mais ne change aucun cadre final ni raccourci. Les anciennes valeurs de durée du rail restent lisibles et héritées lors de l’activation. Le mainteneur vérifie les courbes par tests purs, les écritures par doubles et le geste par la matrice native et ses observations.

## Clarification utilisateur
Roadie reste indépendant de macOS pour les animations. L’interrupteur et les profils Roadie font seuls autorité. Aucun champ de respect automatique du système n’est conservé ; aucune préférence macOS n’est modifiée.
