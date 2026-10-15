# Plan

Remplacer uniquement la saisie dessinée par un NSTextField dans un NSPanel non
activant qui peut devenir key. AppKit gère le texte, le caret, la sélection, le
presse-papiers, l'annulation et les méthodes de saisie. La session conserve ses
modèles de recherche/commandes et intercepte seulement navigation et validation.
Le tap global ne consomme plus les touches de texte du mode recherche.

Le panneau transparent existant garde les badges, compteur, suggestions et messages.
Le vrai champ occupe exactement le cadre de contenu déjà calculé. Le dessin de
texte est désactivé à l'exécution, conservé pour les rendus hors écran existants.
Les clics de suggestions utilisent les mêmes lignes et la même fenêtre de liste
visible que le dessin ; ils sont consommés avant l'application sous-jacente.

Les modèles gagnent un remplacement complet de saisie et une sélection explicite
de suggestion. Pas de réimplémentation de l'édition, de dépendance ni de stockage.
Tester les vrais contrôles AppKit et la synchronisation sans écraser la sélection
lors d'un rafraîchissement des cibles. Vérifier les touches système conservées.

Références primaires :
- https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded
- https://developer.apple.com/documentation/appkit/nsview/needspaneltobecomekey
