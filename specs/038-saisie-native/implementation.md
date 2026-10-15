# Implémentation 038

La saisie dessinée est remplacée par un NSTextField dans un NSPanel non activant.
AppKit possède le texte, la sélection, le caret et les commandes d’édition. Le
panneau dirige les raccourcis Édition vers son propre éditeur, sans menu global.
Le tap global laisse passer le clavier et consomme uniquement les clics de liste.

Les modèles reçoivent le texte entier après édition ; le remplacement d’une
sélection et l’édition au milieu restent possibles. Un rafraîchissement qui garde
le même texte ne remplace pas le contenu natif. Les majuscules restent du texte.

Haut/Bas parcourent les suggestions. À vide, ou sans suggestion, l’historique reste
accessible. Tab insère le choix. Retour accepte le choix puis exécute. Un clic
insère la ligne visée sans exécution immédiate. La géométrie du clic est celle du
dessin, y compris après défilement et changement de police. Le nettoyage ferme
le champ avant l’action différée ou l’ouverture des réglages.

Validation : 127 tests ciblés / 10 suites puis 1 597 tests / 185 suites.
Les tests utilisent un vrai panneau et son éditeur AppKit : ⌘A, remplacement,
accents, suppression par mot, édition centrale et sélection conservée.
La boucle native sur le Release installé vérifie les raccourcis et le clic réel.
Les limites et l’identité de livraison sont dans validation/livraison038.md.
