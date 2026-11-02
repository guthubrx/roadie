# ADR027 — Gestes explicites depuis le contenu

Date :2novembre2026. Statut : accepté. Session151.

## Contexte
Les déplacements natifs partent du titre et les redimensionnements des bords. L’utilisateur valide Ctrl+glisser gauche pour déplacer et Ctrl+Alt+glisser gauche pour redimensionner depuis tout point du contenu. Les combinaisons doivent être réglables dans Roadie. Un second writer d’aperçu provoquerait des conflits de générations et des remises en place concurrentes.

## Décision
Un contrôleur de capture est installé seulement dans le processus écrivain interactif tiler/run. Son contexte C réutilise KeyEventTapOwners. Le tap de titre existant laisse les pressions modifiées à ce contrôleur, quel que soit l’ordre des taps. Le choix des touches lit uniquement publishedConfig, déjà en mémoire ; currentConfig peut faire un stat et reste réservé aux chemins de rechargement.
Le down est réservé. Au-delà du seuil existant8points, la géométrie est préparée une fois. Sans glisser, la paire down/up originale est rejouée avec un marqueur reconnu par les moniteurs du rail et de geste. Une cible disparue ou recouverte ne reçoit aucun clic rejoué. Le menu contextuel Ctrl+clic doit être vérifié en natif. La combinaison exacte décide du mode ; si les réglages sont identiques, le resize est prioritaire.
Un runtime unique utilise InteractiveFrameDispatcher pour la source et toutes les voisines. Déplacement : DropPreviewEngine pour la géométrie, StageCommandService pour la transaction. Le nouveau chemin optionnel deferGeometryUsing persiste sans acquisition ni écriture AX ; la passe normale reprend les écarts après le dépôt. Resize : BSPNativeResize expose seulement ses bords internes mobiles ; le cadre demandé vient du point de départ et du déplacement. Les résultats réels du writer servent au ratio final. Les autres modes conservent le chemin historique du maintainer.
Le verrou UserInputActivity tient jusqu’à la fin du lot. Échap restaure les cadres encore valides ; une nouvelle commande révoque le permis sans rétablir une vieille disposition. Les validations JSON sont bornées à4Hz et au relâchement ; aucun recalcul si le pointeur reste immobile. Un relâchement physique manqué n’est cru qu’après observation du bouton réellement enfoncé.

## Conséquences
Pas de dépendance BTT pour le produit, pas de nouvelle permission demandée. BTT peut servir de pilote de validation sur ce poste déjà autorisé. Un clic modifié sans déplacement arrive à l’application au relâchement ; ce léger report permet de ne pas cliquer sur un lien avant d’avoir reconnu le geste. Une fenêtre tuilée seule n’a pas de séparation interne à réduire. Une application peut imposer une taille ou refuser une écriture ; les budgets et refus du writer commun restent actifs. Une lecture AX déjà partie ne peut pas être interrompue physiquement.

Sources primaires consultées : [CGEvent et injection](https://developer.apple.com/documentation/coregraphics/cgevent), [création d’un tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)). La capture utilise cgSessionEventTap ; aucun accès au tap HID privilégié n’est demandé. Les essais synthétiques restent distincts d’un enregistrement physique de la souris.
