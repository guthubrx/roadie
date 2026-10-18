# Validation 052

## Nettoyage réel

Les douze stages vides du bureau 2 de l'écran intégré ont été supprimées avec
la commande officielle stage delete, après sauvegarde intégrale du fichier.
Le contrôle avant chaque suppression vérifie qu'elle reste vide et inactive.
Les quatre stages occupées et leurs dix membres sont conservés. Trois noms
configurés (Work, Perso, Com) sont recréés par la configuration ; leur présence
n'est pas une nouvelle copie du parking. La nouvelle priorité les place après
les stages occupées. Aucune autre stage n'a été supprimée automatiquement.

Preuves hors Git : /Users/moi/.roadies/diagnostics/2026-10-18-session052/,
stages-avant.json, suppression.json et stages-apres-nettoyage.json.

## Rail et parking

Le panneau garde la hauteur de l'écran. Les cartes forment le document défilable
d'un NSScrollView ; les points de clic sont convertis dans ce document. Le test
avec trente cartes atteint la dernière et vérifie sa destination après défilement.
L'ordre partagé donne priorité aux stages représentées occupées, sans changer
les identifiants persistants. Menus et fantôme utilisent le même ordre.

Le parking réutilise un emplacement vide compatible unique, ou sa même origine
logique. Les stages occupées et les homonymes vides ambigus ne sont pas fusionnés.
Un ancien arbre sans membres n'empêche plus de réutiliser un emplacement vide.
Quatre cycles supérieurs à 60 secondes gardent le nombre de stages et leurs
membres. Les tests de placeholder modifié et de retour tardif restent exécutés.

## A-11

Le ciblage au clic consulte uniquement la copie du dernier snapshot publié :
aucune lecture disque, AX ou reconstruction à ce point. La frame de départ reste
celle mémorisée au clic ; les écritures Roadie actualisent cette copie. Un callback
unique au premier mouseDragged actualise le relevé, sans réinterpréter l'ancrage.
Une poignée acceptée efface le geste natif avant ce callback. Le journal de cible
est déplacé au début du glisser, plutôt qu'écrit à chaque clic simple.

## V15

Correction distincte commitée et poussée dans 00.Generic : 744f30b.
Option run --tool gitleaks-history --history-since REF, borne exclusive résolue
en SHA et fin figée au commit du manifeste. Le reçu history_scope et la
justification du contrôle indiquent la portée ; aucun succès global de l'audit
n'est inventé. Scanner absent, erreur et budget restent des limites réelles.

63 tests Python sur l'environnement courant, puis 39 tests sur une copie isolée
du commit de base et des seules modifications de cette tâche. Les modifications
préexistantes de l'outil (notes par axe notamment) restent intactes et hors de
ce commit. Contrôle réel Roadie depuis v0.4.0 : completed, zéro candidat,
aucun avertissement de normalisation, plage et SHA dans audit-historique.log.
Ce contrôle est une recherche de secrets sur une plage, pas un audit complet.

## Tests, installation et limites

1 749 tests Swift dans 209 suites réussis. Les anciennes attentes de rang des
cartes vides sont adaptées à la priorité validée, et la concordance entre aperçu
et dépôt reste vérifiée pour tous les modes de rendu existants. Aucun benchmark.

Compilation Release réussie et installation vérifiée ; UUID compilé/installé
302CADB3-689D-3EF0-88D0-37693C9168F4. Signature stricte vérifiée, certificat
78a75e8032f190a20072eb91cc2919aac344ef78 conservé. Configuration inchangée.
Redémarrage vérifié, PID 69262, cinq contrôles santé OK. CoreGraphics confirme
un panneau de rail de 150 × 1 125 points sur l'écran de 1 125 points de haut.
Après installation, les quatre stages occupées et leurs dix membres sont conservés.
Les 302 empreintes Sources/Tests sont inchangées depuis la suite verte.
Une revue indépendante a été proposée, sans accord reçu à ce stade ; aucune revue
externe n'est revendiquée. Contrôles et relecture réalisés par le responsable.
Preuves visuelles incomplètes : screencapture échoue avec « could not create image
from display ». Aucun diaporama fabriqué. Le rebranchement physique de l'écran
externe n'est pas réalisable à distance ; les cycles sont vérifiés en tests.
