# Validation 053 - Dépôt fidèle dans le rail

## Demande et décisions

L'utilisateur confirme que le point de dépôt fait foi : haut, interstice et bas.
Un dépôt sur une carte rejoint sa stage. L'ordre persistant remplace la partition
automatique occupées/vides. Le rail reste défilable, sans nouvelle option à régler.
Une ancienne stage anonyme devenue vide reste masquée comme auparavant ; cela
compacte la liste sans réordonner les autres stages ni modifier la destination.

## Reproductions

Les deux derniers événements réels d'affectation confirment les écrans et stages,
mais n'avaient pas de coordonnées de dépôt. Ils ne suffisent pas à prouver la
position visée. Etat initial et quatre événements archivés hors Git dans
/Users/moi/.roadies/diagnostics/2026-10-21-session053/.

Avant correction, neuf assertions échouent : position du bas non transmise,
rang non persisté sur un/deux écrans, ordre changé quand une carte vide se remplit.
Après une première correction par rang, huit assertions supplémentaires échouent
si une stage est ajoutée en arrière-plan entre la prise de cible et le dépôt.
La destination est donc portée par un identifiant de voisin ou la fin de liste,
puis résolue dans la transaction verrouillée d'affectation.

## Revue et décisions

Revue indépendante en lecture seule, sans shell/diff ni écran chez le réviseur.
Le responsable relit le diff, exécute les tests et assume les corrections.

- D1 : ancre stable et calcul sous verrou ajoutés. Le slot doit encore être vide,
  anonyme et non parqué ; une ancre disparue fait échouer sans mutation.
- D2 : retrait du repli vers le panneau source lorsque le panneau destination
  manque. Panneau et écran sont choisis ensemble.
- D3 : disparition de la carte source anonyme vide conservée ; aucune suppression
  persistante ni réorganisation des autres cartes. Ce comportement est distinct
  du tri automatique retiré à la demande de l'utilisateur.
- Haut/milieu/bas, défilement, aperçu transparent à la souris et concurrence sont
  couverts par les tests. Le gel d'une reconstruction asynchrone est relu dans le
  contrôleur ; son parcours réel reste à vérifier sur un bureau accessible.

Le repère « Nouvelle stage » indique l'emplacement ; le survol d'une carte la met
en évidence. L'aperçu et le dépôt utilisent la même sélection. Aucun trait bleu.
Au relâchement, le journal indique le point en coordonnées écran NS, le type de
cible, son écran, sa stage et l'ancre demandée. Pas de relevé AX par mouvement.

## Complexité, simplicité et limites

Sélection et aperçu linéaires dans les cartes ; résolution du rang linéaire dans
les stages lors du seul dépôt. Réutilisation de la transaction existante, sans
nouvelle dépendance. La copie de la liste persistante à chaque mouvement a été
retirée grâce à l'ancre. Le calcul du voisin reste répété pour placer le repère :
il porte sa géométrie, sans stocker un état de destination qui pourrait diverger.
Pas de gain de performance chiffré revendiqué.

Preuves visuelles incomplètes : CUA renvoie « CUA_REPL_ENABLED_SURFACES is required »
et screencapture « could not create image from display ». Aucun clic aveugle,
aucune demande répétée d'autorisation macOS, aucun diaporama fabriqué.

## Vérifications

95 tests ciblés réussis, puis 1 758 tests dans 210 suites après les derniers cas
de refus de destination et le retrait du repli de panneau. Les trois cas de refus
vérifient l'identité des octets persistés avant/après. 303 empreintes Sources/Tests
conservées avant compilation Release et vérifiées inchangées après installation.

Release compilée et installée ; UUID
458CF5AB-3B7E-3F5A-9B09-656E7B0FF331 identique entre binaire compilé et installé.
Signature stricte vérifiée ; certificat 78a75e8032f190a20072eb91cc2919aac344ef78
et configuration inchangés. Redémarrage terminé, PID 81466, cinq contrôles santé OK.
Recette temporaire d'installation à deux tâches retirée. Essai utilisateur proposé
sur les trois positions ; aucun résultat manuel revendiqué à ce stade.

Correction cffaf5c6 intégrée et poussée sur main. Branche de session supprimée,
fichiers de compilation et recette temporaire retirés. Worktree de cette
conversation conservé détaché. Diagnostic, sauvegarde et reçus conservés hors Git.

## Complément : carte vide invisible après plusieurs dépôts

L'utilisateur confirme plusieurs dépôts corrects et fournit une capture horodatée
06:29:19Z. La sauvegarde initiale situe X dans « Perso » (stage 2). L'événement
06:28:51Z le déplace vers une nouvelle stage 4 avant la stage 9. À 06:29:24Z, Firefox
remplit « Perso ». La capture se trouve entre ces deux actions : la carte nommée
est vide, avec un libellé expiré. Le membre fermé de la stage 6 est distinct.
Le test de reconstructions successives 9/8/9/7/8 cartes conserve les écarts :
aucune correction de géométrie n'est nécessaire.

L'ancien test de la session 031 exigeait l'invisibilité des cartes vides après
expiration. Douze assertions de pixels échouent avant le correctif sur les quatre
rendus. Elles passent après : contour et texte permanents, police de légende
configurée, numéro futur reflété par le fantôme, libellés occupés toujours temporaires.
La suite complète réussit : 1 760 tests dans 210 suites après le test de panneau ajouté suite à la revue. Aucun benchmark.

Preuves visuelles incomplètes pour le nouveau rendu : la capture utilisateur
documente le symptôme ; CUA renvoie toujours « CUA_REPL_ENABLED_SURFACES is required ».
Aucune capture de résultat ni geste réel automatisé ne sont revendiqués.

Revue du complément en lecture seule (pas de shell/diff ni écran côté réviseur) :
- Objection sur les cartes anonymes vides : chemin exclu par StagePresentationOrder,
  confirmé par le test du panneau complet avec slot anonyme et carte nommée.
- Texte : le test compare deux noms après désactivation des libellés ; le panneau
  complet compare aussi le rendu nommé à « Vide » seul, avec nom court ou très long.
  Le débordement des pixels après troncature reste non vérifié à l'écran.
- Fantôme : Spec041RailReorderPreviewTests vérifie déjà les pixels du numéro futur
  et du nom personnel, ainsi que l'original inchangé.
- Couleur neutre et opacité du contour conservées intentionnellement : ce repère
  de destination reste lisible quand l'opacité/visibilité des libellés est nulle.
  La famille et la taille de légende configurées restent utilisées.

Installation du complément : UUID DAF8ED16-F7D6-30AE-A800-A338ACEF5027 identique
entre binaire Release et app installée. Signature stricte vérifiée, certificat
78a75e8032f190a20072eb91cc2919aac344ef78 et configuration inchangés.
Sources de production inchangées entre tests complets, build et installation ;
seul le test du panneau complet a été ajouté après le build, puis tous les
1 760 tests / 210 suites ont été relancés avec succès.
Redémarrage terminé, PID 27951, cinq contrôles santé OK.
L'utilisateur autorise désormais toutes les revues indépendantes sans nouvelle
question ; préférence enregistrée dans les instructions globales et projet.
