# Implémentation

## Légendes

- Nouveaux réglages `caption_font_size`, `gap` et `follows_perspective` dans
  `fx.rail.stage_labels`. Catalogue, parseur, statut et validateur concordent.
- Taille 0 : héritage de la taille des détails. Une taille explicite ne change pas
  les lettres, les compteurs ni les menus du rail.
- Légende sur le contour effectivement projeté de l'aperçu de devant. Perspective
  optionnelle : même transformation affine, avec réserve de sa hauteur projetée.
- Le bloc compact réserve le texte et son écart sous l'aperçu. Réserve de couches
  bornée à huit points pour éviter une collision avec la case précédente.
- Mesure de police mise en cache dans chaque carte. Aucun saut pendant l'apparition
  et la disparition des noms ; les groupes vides gardent une case de même hauteur.
- Le numéro et le nom utilisent toujours le mécanisme de révélation de la session 031.

## Placement Outlook

Le signal de destruction est conservé en mémoire tant que CoreGraphics présente
encore la fenêtre. Il peut alors retirer une feuille vivante à chaque réconciliation.
Le cas Outlook/Teams/T3 est reproduit par un signal ancien : six assertions échouent,
dont l'arbre réduit à deux feuilles et le retour d'Outlook au bas gauche.

Un placement explicite confirme maintenant la fenêtre présente dans un relevé récent.
Il révoque seulement son signal antérieur à la commande, avant d'appliquer la mutation.
Une fermeture plus récente reste prioritaire ; les autres fenêtres ne changent pas.
L'événement `window_destruction_retracted` permet de tracer cette décision.

Tests : dépôt avec et sans ancien signal, correspondance entre aperçu et placement,
conservation au cycle suivant, nouvelle fermeture après le dépôt, signal plus récent
que la demande de placement. Les tests de fermeture existants sont conservés.

Vérification complémentaire du geste complet : `Spec033DragFlowTests` utilise les
contrôleurs réels de déplacement et de maintien, avec des fenêtres et des écritures
isolées. Il rejoue deux dépôts sous Teams aux coordonnées négatives de l'incident.
L'aperçu, les trois cadres, l'arbre et trois cycles de maintien par dépôt sont vérifiés.
Le scénario passe avec et sans ancien signal de destruction.

Sans l'appel de confirmation du placement, le même test échoue sur 27 assertions :
Outlook revient au bas gauche, Teams garde la colonne droite entière, alors que
les deux gestes sont annoncés acceptés. L'appel a été rétabli avant la suite complète.
Aucune nouvelle modification du code de production ni du groupe actuel n'est nécessaire.

## Validation

Les tests ciblés des légendes passent : perspectives activée/désactivée, écart 0/4/12,
zéro à cinq fenêtres, absence de collision, limites, réglages indépendants et fondu.
Le test de dépôt du rail vise maintenant le centre dessiné de la vignette, qui ne
coïncide plus avec le centre de la carte contenant sa légende.

Le mode concurrent de Swift Testing fait dépasser le délai de cinq secondes du
serveur de test lorsqu'AppKit exécute les rendus et les balayages de clics. Le groupe
UI seul prend 2,98 secondes. Les balayages cèdent le fil entre les lots de lignes.
Validation complète avec le mode séquentiel officiel `swift test --no-parallel` :
La suite isolée initiale compte 1 482 tests réussis. Le nouveau test de geste passe
aussi sur cette branche dans ses deux cas. La suite combinée complète compte
maintenant 1 550 tests réussis dans 168 suites. Aucun délai ni assertion IPC n'a été
augmenté ou supprimé.

Revue locale : pas de nouveau moteur, aucune modification des raccourcis, aucune
suppression de groupe, traitement de destruction borné à la fenêtre explicitement
placée et à un signal plus ancien. Les anciennes notifications de fermeture des
fenêtres absentes restent prioritaires.
