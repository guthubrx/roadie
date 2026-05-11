# Recherche : Menu Pin et Repliage

## Décision 1 : contrôle visible comme overlay Roadie

**Décision** : dessiner un contrôle circulaire bleu Roadie au-dessus de la zone de titre probable des fenêtres pinées, sans modifier la vraie barre de titre de l'application.

**Justification** : macOS ne permet pas d'injecter proprement un contrôle universel dans les barres de titre des applications tierces. Un overlay Roadie garde la fonctionnalité maîtrisable, désactivable et compatible avec les apps à barre de titre personnalisée.

**Alternatives étudiées** :

- Injection dans la barre de titre native : rejetée, trop fragile et non universelle.
- Clic droit uniquement : rejeté, car la fonctionnalité demandée vise précisément un point d'entrée visible.
- Bouton dans le navrail : rejeté pour cette feature, car l'action porte sur une fenêtre précise.

## Décision 2 : repliage par proxy Roadie

**Décision** : replier une fenêtre pinée en cachant ou déplaçant la vraie fenêtre selon les mécanismes Roadie existants, puis afficher un proxy compact Roadie qui permet de la restaurer.

**Justification** : le "window shading" historique réduit la fenêtre à sa barre de titre, mais les applications macOS modernes peuvent imposer une hauteur minimale ou réagir différemment au redimensionnement. Un proxy Roadie donne une expérience stable : la fenêtre ne masque plus le dessous, mais l'utilisateur garde une poignée de restauration.

**Alternatives étudiées** :

- Redimensionner réellement la fenêtre à la hauteur de titre : rejeté pour v1, car le comportement varie selon les applications.
- Minimiser la fenêtre via macOS : rejeté, car cela sort la fenêtre du modèle Roadie et rend la restauration moins locale au pin.
- Rendre la fenêtre click-through : rejeté, pas fiable pour les apps tierces et confus pour l'utilisateur.

## Décision 3 : état de présentation persistant avec les pins

**Décision** : rattacher l'état visible/replié d'une fenêtre pinée à l'état persistant des pins, avec conservation du frame précédent.

**Justification** : le repliage est une propriété du pin, pas seulement un effet visuel temporaire. Il doit survivre aux snapshots et rester cohérent pendant les changements de stage/desktop.

**Alternatives étudiées** :

- État uniquement mémoire dans le contrôleur : rejeté, car il serait perdu à la relance ou lors d'un refresh.
- Fichier séparé `pin-popover.json` : rejeté, car il ajouterait une deuxième source de vérité à synchroniser avec `StageStore`.

## Décision 4 : configuration expérimentale dédiée

**Décision** : ajouter une section `[experimental.pin_popover]` avec activation, placement, taille et options de repliage.

**Justification** : l'overlay permanent est plus visible et plus intrusif que le menu clic droit. Il doit être contrôlable indépendamment, désactivable rapidement, et validé avant activation par défaut.

**Alternatives étudiées** :

- Réutiliser uniquement `[experimental.titlebar_context_menu]` : rejeté, car le bouton visible et le proxy ont des réglages propres.
- Activer sans réglage : rejeté, car la sûreté de placement dépend des apps.

## Décision 5 : réutilisation des actions existantes

**Décision** : le menu du bouton appelle les mêmes actions métier que le menu de barre de titre, via `WindowContextActions` et les destinations existantes.

**Justification** : le menu bouton est un second point d'entrée UX, pas une nouvelle logique de déplacement. Réutiliser les actions évite les divergences entre clic droit et bouton.

**Alternatives étudiées** :

- Recréer les actions dans le nouveau contrôleur : rejeté, risque de divergence et de bugs stage/desktop/display.
- Forcer le focus sur la fenêtre puis utiliser les commandes actives : rejeté, car cela introduirait des changements de focus non demandés.

## Décision 6 : placement conservateur

**Décision** : si le bouton ne peut pas être placé sans ambiguïté dans une zone sûre, Roadie ne l'affiche pas pour cette fenêtre.

**Justification** : couvrir un bouton natif ou un contrôle applicatif est plus coûteux qu'une absence de bouton. L'utilisateur conserve toujours le menu clic droit de barre de titre comme fallback.

**Alternatives étudiées** :

- Toujours afficher avec un offset fixe : rejeté, car les apps ont des toolbars différentes.
- Afficher au centre de la fenêtre : rejeté, car cela polluerait le contenu applicatif.
